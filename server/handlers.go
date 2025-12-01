package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"math/big"
	mrand "math/rand"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/gorilla/websocket"
	"github.com/rs/zerolog/log"
)

// Player represents a player in a room
type Player struct {
	ID         string          `json:"player_id"`
	Name       string          `json:"name"`
	Token      string          `json:"-"`
	Ready      bool            `json:"ready"`
	Scores     map[string]int  `json:"scores"`
	TotalScore int             `json:"total_score"`
	IsViewer   bool            `json:"is_viewer"` // True if player rejoined after game started
	LastSeen   time.Time       `json:"-"`
	Conn       *websocket.Conn `json:"-"`
	ConnMutex  sync.Mutex      `json:"-"`
}

// GameEvent represents a game event
type GameEvent struct {
	ID      int                    `json:"id"`
	Type    string                 `json:"type"`
	Payload map[string]interface{} `json:"event"`
}

// Room represents a game room
type Room struct {
	Code             string             `json:"room_code"`
	Players          map[string]*Player `json:"players"`
	PlayerOrder      []string           `json:"-"`
	CurrentPlayerIdx int                `json:"-"`
	CurrentDice      []int              `json:"-"`
	RollsLeft        int                `json:"-"`
	GameStarted      bool               `json:"-"`
	HostID           string             `json:"-"` // Original host (room creator)
	Events           []GameEvent        `json:"-"`
	EventMutex       sync.RWMutex       `json:"-"`
	PlayerMutex      sync.RWMutex       `json:"-"`
	LastActivity     time.Time          `json:"-"`
}

// GameManager manages all game rooms
type GameManager struct {
	rooms    map[string]*Room
	mutex    sync.RWMutex
	upgrader websocket.Upgrader
}

// Categories for Yahtzee
var Categories = []string{
	"ones", "twos", "threes", "fours", "fives", "sixes",
	"three_of_a_kind", "four_of_a_kind", "full_house",
	"small_straight", "large_straight", "yahtzee",
}

// NewGameManager creates a new game manager
func NewGameManager() *GameManager {
	return &GameManager{
		rooms: make(map[string]*Room),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for game clients
			},
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
	}
}

// generateRoomCode creates a random 6-character room code
func generateRoomCode() string {
	const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	code := make([]byte, 6)
	for i := range code {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(letters))))
		code[i] = letters[n.Int64()]
	}
	return string(code)
}

// generateToken creates a random auth token
func generateToken() string {
	bytes := make([]byte, 32)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

// generatePlayerID creates a random player ID
func generatePlayerID() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

// CleanupExpiredRooms removes rooms with no activity
func (gm *GameManager) CleanupExpiredRooms(timeout time.Duration) {
	ticker := time.NewTicker(5 * time.Minute)
	for range ticker.C {
		gm.mutex.Lock()
		now := time.Now()
		for code, room := range gm.rooms {
			if now.Sub(room.LastActivity) > timeout {
				// Close all player connections
				room.PlayerMutex.RLock()
				for _, player := range room.Players {
					if player.Conn != nil {
						player.Conn.Close()
					}
				}
				room.PlayerMutex.RUnlock()
				delete(gm.rooms, code)
				log.Info().
					Str("room_code", code).
					Msg("Cleaned up expired room")
			}
		}
		gm.mutex.Unlock()
	}
}

// CreateRoom handles POST /rooms
func (gm *GameManager) CreateRoom(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PlayerName string `json:"player_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.PlayerName == "" {
		req.PlayerName = "Player"
	}

	gm.mutex.Lock()
	defer gm.mutex.Unlock()

	// Generate unique room code
	var roomCode string
	for {
		roomCode = generateRoomCode()
		if _, exists := gm.rooms[roomCode]; !exists {
			break
		}
	}

	playerID := generatePlayerID()
	token := generateToken()

	player := &Player{
		ID:       playerID,
		Name:     req.PlayerName,
		Token:    token,
		Ready:    false,
		Scores:   make(map[string]int),
		LastSeen: time.Now(),
	}

	room := &Room{
		Code:         roomCode,
		Players:      map[string]*Player{playerID: player},
		PlayerOrder:  []string{playerID},
		HostID:       playerID, // Set the original host
		CurrentDice:  []int{1, 1, 1, 1, 1},
		RollsLeft:    3,
		Events:       []GameEvent{},
		LastActivity: time.Now(),
	}

	gm.rooms[roomCode] = room

	log.Info().
		Str("room_code", roomCode).
		Str("player_id", playerID).
		Str("player_name", req.PlayerName).
		Msg("Created room")

	json.NewEncoder(w).Encode(map[string]interface{}{
		"room_code":     roomCode,
		"player_id":     playerID,
		"token":         token,
		"last_event_id": 0,
	})
}

// JoinRoom handles POST /rooms/join
func (gm *GameManager) JoinRoom(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RoomCode   string `json:"room_code"`
		PlayerName string `json:"player_name"`
		PlayerID   string `json:"player_id"` // Optional: for rejoin
		Token      string `json:"token"`     // Optional: for rejoin
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.PlayerName == "" {
		req.PlayerName = "Player"
	}

	gm.mutex.RLock()
	room, exists := gm.rooms[req.RoomCode]
	gm.mutex.RUnlock()

	if !exists {
		log.Debug().
			Str("room_code", req.RoomCode).
			Str("player_name", req.PlayerName).
			Msg("Join attempt to non-existent room")
		http.Error(w, "Room not found", http.StatusNotFound)
		return
	}

	room.PlayerMutex.Lock()
	defer room.PlayerMutex.Unlock()

	// Check if this is a rejoin attempt with valid credentials
	if req.PlayerID != "" && req.Token != "" {
		if existingPlayer, exists := room.Players[req.PlayerID]; exists {
			if existingPlayer.Token == req.Token {
				// Valid rejoin - update name and last seen
				existingPlayer.Name = req.PlayerName
				existingPlayer.LastSeen = time.Now()

				// Check if player is still in PlayerOrder (they can still play)
				isInOrder := false
				for _, pid := range room.PlayerOrder {
					if pid == req.PlayerID {
						isInOrder = true
						break
					}
				}

				// If game has started OR player is not in order (they left), they're a viewer
				// Once you leave, you can't come back as an active player
				isViewer := room.GameStarted || !isInOrder
				existingPlayer.IsViewer = isViewer

				room.LastActivity = time.Now()

				log.Info().
					Str("room_code", req.RoomCode).
					Str("player_id", req.PlayerID).
					Str("player_name", req.PlayerName).
					Bool("is_viewer", isViewer).
					Bool("is_in_order", isInOrder).
					Msg("Player rejoined room")

				json.NewEncoder(w).Encode(map[string]interface{}{
					"room_code":     req.RoomCode,
					"player_id":     req.PlayerID,
					"token":         req.Token,
					"is_viewer":     isViewer,
					"last_event_id": len(room.Events),
				})
				return
			}
		}
		// Invalid rejoin credentials - fall through to create new viewer if game started
	}

	// If game has started, allow joining as viewer only
	if room.GameStarted {
		// Create a new viewer player
		playerID := generatePlayerID()
		token := generateToken()

		player := &Player{
			ID:       playerID,
			Name:     req.PlayerName,
			Token:    token,
			Ready:    false,
			Scores:   make(map[string]int),
			IsViewer: true, // Always a viewer if joining after game started
			LastSeen: time.Now(),
		}

		room.Players[playerID] = player
		// Don't add to PlayerOrder - viewers can't play
		room.LastActivity = time.Now()

		log.Info().
			Str("room_code", req.RoomCode).
			Str("player_id", playerID).
			Str("player_name", req.PlayerName).
			Msg("New viewer joined room")

		json.NewEncoder(w).Encode(map[string]interface{}{
			"room_code":     req.RoomCode,
			"player_id":     playerID,
			"token":         token,
			"is_viewer":     true,
			"last_event_id": len(room.Events),
		})
		return
	}

	// New player join - only allowed if game hasn't started

	if len(room.Players) >= 6 {
		log.Debug().
			Str("room_code", req.RoomCode).
			Str("player_name", req.PlayerName).
			Int("player_count", len(room.Players)).
			Msg("Join attempt to full room")
		http.Error(w, "Room is full", http.StatusForbidden)
		return
	}

	playerID := generatePlayerID()
	token := generateToken()

	player := &Player{
		ID:       playerID,
		Name:     req.PlayerName,
		Token:    token,
		Ready:    false,
		Scores:   make(map[string]int),
		IsViewer: false,
		LastSeen: time.Now(),
	}

	room.Players[playerID] = player
	room.PlayerOrder = append(room.PlayerOrder, playerID)
	room.LastActivity = time.Now()

	log.Info().
		Str("room_code", req.RoomCode).
		Str("player_id", playerID).
		Str("player_name", req.PlayerName).
		Int("player_count", len(room.Players)).
		Msg("Player joined room")

	json.NewEncoder(w).Encode(map[string]interface{}{
		"room_code":     req.RoomCode,
		"player_id":     playerID,
		"token":         token,
		"is_viewer":     false,
		"last_event_id": len(room.Events),
	})
}

// WebSocket handles GET /rooms/{roomCode}/ws
func (gm *GameManager) WebSocket(w http.ResponseWriter, r *http.Request) {
	roomCode := chi.URLParam(r, "roomCode")
	playerID := r.URL.Query().Get("player_id")
	token := r.URL.Query().Get("token")

	gm.mutex.RLock()
	room, exists := gm.rooms[roomCode]
	gm.mutex.RUnlock()

	if !exists {
		log.Debug().
			Str("room_code", roomCode).
			Str("player_id", playerID).
			Msg("WebSocket connection to non-existent room")
		http.Error(w, "Room not found", http.StatusNotFound)
		return
	}

	// Verify player token
	room.PlayerMutex.RLock()
	player, playerExists := room.Players[playerID]
	room.PlayerMutex.RUnlock()

	if !playerExists || player.Token != token {
		log.Warn().
			Str("room_code", roomCode).
			Str("player_id", playerID).
			Bool("player_exists", playerExists).
			Msg("WebSocket connection unauthorized")
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Upgrade to WebSocket
	conn, err := gm.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Error().
			Err(err).
			Str("room_code", roomCode).
			Str("player_id", playerID).
			Msg("WebSocket upgrade failed")
		return
	}

	// Store connection
	player.ConnMutex.Lock()
	oldConn := player.Conn
	player.Conn = conn
	player.ConnMutex.Unlock()

	// Close old connection if exists
	if oldConn != nil {
		oldConn.Close()
		log.Debug().
			Str("room_code", roomCode).
			Str("player_id", playerID).
			Msg("Closed previous WebSocket connection")
	}

	log.Info().
		Str("room_code", roomCode).
		Str("player_id", playerID).
		Msg("WebSocket connected")

	// Send viewer status to reconnecting player
	if player.IsViewer {
		gm.sendToPlayer(player, map[string]interface{}{
			"type":      "VIEWER_MODE",
			"player_id": playerID,
			"message":   "You are viewing this game. You cannot interact.",
		})

		// If game has started, send complete current game state
		if room.GameStarted {
			room.PlayerMutex.RLock()
			playersData := make(map[string]interface{})
			playersList := make([]map[string]interface{}, 0, len(room.PlayerOrder))

			// Build player list in turn order (active players only)
			for _, pid := range room.PlayerOrder {
				if p, exists := room.Players[pid]; exists {
					pData := map[string]interface{}{
						"player_id":   pid,
						"name":        p.Name,
						"ready":       p.Ready,
						"total_score": p.TotalScore,
						"scores":      p.Scores,
					}
					playersData[pid] = pData
					playersList = append(playersList, pData)
				}
			}

			// Also include all players (including viewers) in the full data
			for id, p := range room.Players {
				if _, exists := playersData[id]; !exists {
					playersData[id] = map[string]interface{}{
						"player_id":   id,
						"name":        p.Name,
						"ready":       p.Ready,
						"total_score": p.TotalScore,
						"scores":      p.Scores,
						"is_viewer":   p.IsViewer,
					}
				}
			}

			currentPlayerID := ""
			if len(room.PlayerOrder) > 0 && room.CurrentPlayerIdx < len(room.PlayerOrder) {
				currentPlayerID = room.PlayerOrder[room.CurrentPlayerIdx]
			}
			room.PlayerMutex.RUnlock()

			// Get event history for viewer
			room.EventMutex.RLock()
			eventHistory := make([]map[string]interface{}, 0, len(room.Events))
			for _, evt := range room.Events {
				// Create a copy of the payload to avoid mutating the original
				eventCopy := make(map[string]interface{})
				for k, v := range evt.Payload {
					eventCopy[k] = v
				}
				eventHistory = append(eventHistory, eventCopy)
			}
			room.EventMutex.RUnlock()

			gm.sendToPlayer(player, map[string]interface{}{
				"type":           "GAME_STATE",
				"players":        playersData,
				"player_list":    playersList,
				"turn_order":     room.PlayerOrder,
				"current_player": currentPlayerID,
				"dice":           room.CurrentDice,
				"rolls_left":     room.RollsLeft,
				"event_history":  eventHistory,
			})
		}
	}

	// Send existing players to new connection (including self)
	room.PlayerMutex.RLock()
	for id, p := range room.Players {
		gm.sendToPlayer(player, map[string]interface{}{
			"type":      "PLAYER_JOINED",
			"player_id": id,
			"name":      p.Name,
			"is_host":   id == room.HostID,
			"is_viewer": p.IsViewer,
		})
	}
	room.PlayerMutex.RUnlock()

	// Broadcast join to all other players (only if not a silent reconnection)
	// For viewers rejoining, we don't need to broadcast
	if !player.IsViewer || !room.GameStarted {
		room.broadcast(map[string]interface{}{
			"type":      "PLAYER_JOINED",
			"player_id": playerID,
			"name":      player.Name,
			"is_host":   playerID == room.HostID,
			"is_viewer": player.IsViewer,
		}, playerID)
	}

	// Handle incoming messages
	gm.handlePlayerMessages(room, player)
}

// handlePlayerMessages reads messages from a player's WebSocket
func (gm *GameManager) handlePlayerMessages(room *Room, player *Player) {
	defer func() {
		player.ConnMutex.Lock()
		if player.Conn != nil {
			player.Conn.Close()
			player.Conn = nil
		}
		player.ConnMutex.Unlock()
		log.Info().
			Str("player_id", player.ID).
			Str("room_code", room.Code).
			Msg("WebSocket disconnected")

		// Handle player disconnection
		gm.handlePlayerDisconnect(room, player)
	}()

	for {
		_, message, err := player.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Warn().
					Err(err).
					Str("player_id", player.ID).
					Str("room_code", room.Code).
					Msg("WebSocket unexpected close error")
			} else {
				log.Debug().
					Err(err).
					Str("player_id", player.ID).
					Str("room_code", room.Code).
					Msg("WebSocket connection closed")
			}
			break
		}

		var event map[string]interface{}
		if err := json.Unmarshal(message, &event); err != nil {
			log.Warn().
				Err(err).
				Str("player_id", player.ID).
				Str("room_code", room.Code).
				Str("message", string(message)).
				Msg("Invalid message from player")
			continue
		}

		room.LastActivity = time.Now()
		player.LastSeen = time.Now()

		// Unwrap event if it's in wrapped format: {"type": "event", "event": {...}}
		eventType, _ := event["type"].(string)
		if eventType == "event" {
			if innerEvent, ok := event["event"].(map[string]interface{}); ok {
				event = innerEvent
				eventType, _ = event["type"].(string)
			}
		}

		// Add player_id to event if not present
		if _, ok := event["player_id"]; !ok {
			event["player_id"] = player.ID
		}

		// Ignore events from viewers
		if player.IsViewer {
			log.Debug().
				Str("player_id", player.ID).
				Str("room_code", room.Code).
				Str("event_type", eventType).
				Msg("Ignoring event from viewer")
			continue
		}

		// Process event as authority
		log.Trace().
			Str("player_id", player.ID).
			Str("room_code", room.Code).
			Str("event_type", eventType).
			Interface("event", event).
			Msg("Processing game event")
		room.processEvent(eventType, event)
	}
}

// sendToPlayer sends a message to a specific player
func (gm *GameManager) sendToPlayer(player *Player, event map[string]interface{}) {
	player.ConnMutex.Lock()
	defer player.ConnMutex.Unlock()

	if player.Conn == nil {
		return
	}

	data, err := json.Marshal(event)
	if err != nil {
		return
	}

	if err := player.Conn.WriteMessage(websocket.TextMessage, data); err != nil {
		log.Warn().
			Err(err).
			Str("player_id", player.ID).
			Msg("Failed to send message to player")
	} else {
		log.Trace().
			Str("player_id", player.ID).
			Str("event_type", event["type"].(string)).
			Interface("event", event).
			Msg("Message sent to player")
	}
}

// broadcast sends an event to all players in a room
func (room *Room) broadcast(event map[string]interface{}, excludePlayerID string) {
	room.PlayerMutex.RLock()
	defer room.PlayerMutex.RUnlock()

	data, err := json.Marshal(event)
	if err != nil {
		return
	}

	for id, player := range room.Players {
		if id == excludePlayerID {
			continue
		}

		player.ConnMutex.Lock()
		if player.Conn != nil {
			if err := player.Conn.WriteMessage(websocket.TextMessage, data); err != nil {
				log.Warn().
					Err(err).
					Str("player_id", id).
					Msg("Failed to broadcast message to player")
			}
		}
		player.ConnMutex.Unlock()
	}
}

// broadcastAll sends an event to all players including sender
func (room *Room) broadcastAll(event map[string]interface{}) {
	log.Trace().
		Str("room_code", room.Code).
		Interface("event", event).
		Msg("Broadcasting event to all players")
	room.broadcast(event, "")
}

// addEvent adds an event to history and broadcasts to all players
func (room *Room) addEvent(eventType string, payload map[string]interface{}) {
	room.EventMutex.Lock()
	payload["type"] = eventType
	event := GameEvent{
		ID:      len(room.Events) + 1,
		Type:    eventType,
		Payload: payload,
	}
	room.Events = append(room.Events, event)
	room.EventMutex.Unlock()

	// Broadcast to all players
	room.broadcastAll(payload)
}

// processEvent handles game logic for incoming events
func (room *Room) processEvent(eventType string, event map[string]interface{}) {
	switch eventType {
	case "PLAYER_READY":
		room.handlePlayerReady(event)
	case "GAME_START", "START_GAME":
		room.handleGameStart(event)
	case "REQUEST_ROLL":
		room.handleRequestRoll(event)
	case "CATEGORY_CHOSEN":
		room.handleCategoryChosen(event)
	case "REQUEST_END_TURN":
		room.handleEndTurn(event)
	case "CHAT_MESSAGE":
		room.addEvent("CHAT_MESSAGE", event)
	}
}

func (room *Room) handlePlayerReady(event map[string]interface{}) {
	playerID, _ := event["player_id"].(string)
	ready, _ := event["ready"].(bool)

	room.PlayerMutex.Lock()
	if player, exists := room.Players[playerID]; exists {
		player.Ready = ready
	}
	room.PlayerMutex.Unlock()

	room.addEvent("PLAYER_READY", event)
}

func (room *Room) handleGameStart(event map[string]interface{}) {
	if room.GameStarted {
		return
	}

	// Validate that only the host can start the game
	playerID, _ := event["player_id"].(string)
	if room.HostID != playerID {
		log.Warn().
			Str("player_id", playerID).
			Str("room_code", room.Code).
			Str("host_id", room.HostID).
			Msg("Non-host player attempted to start game")
		return
	}

	room.GameStarted = true
	room.RollsLeft = 3
	room.CurrentDice = []int{1, 1, 1, 1, 1}

	// Shuffle player order randomly
	shuffledOrder := make([]string, len(room.PlayerOrder))
	copy(shuffledOrder, room.PlayerOrder)
	mrand.Shuffle(len(shuffledOrder), func(i, j int) {
		shuffledOrder[i], shuffledOrder[j] = shuffledOrder[j], shuffledOrder[i]
	})
	room.PlayerOrder = shuffledOrder
	room.CurrentPlayerIdx = 0

	room.PlayerMutex.Lock()
	playersData := make(map[string]interface{})
	playersList := make([]map[string]interface{}, 0, len(room.Players))
	for id, p := range room.Players {
		p.Scores = make(map[string]int)
		p.TotalScore = 0
		pData := map[string]interface{}{
			"player_id":   id,
			"name":        p.Name,
			"ready":       p.Ready,
			"total_score": 0,
		}
		playersData[id] = pData
		playersList = append(playersList, pData)
	}
	room.PlayerMutex.Unlock()

	firstPlayer := ""
	if len(room.PlayerOrder) > 0 {
		firstPlayer = room.PlayerOrder[0]
	}

	room.addEvent("GAME_STARTED", map[string]interface{}{
		"players":        playersData,
		"player_list":    playersList,
		"turn_order":     room.PlayerOrder,
		"current_player": firstPlayer,
	})

	log.Info().
		Str("room_code", room.Code).
		Str("current_player", firstPlayer).
		Int("player_count", len(room.Players)).
		Msg("Game started")
}

func (room *Room) handleRequestRoll(event map[string]interface{}) {
	playerID, _ := event["player_id"].(string)
	heldIndices, _ := event["held_indices"].([]interface{})

	// Validate turn
	if len(room.PlayerOrder) == 0 || room.PlayerOrder[room.CurrentPlayerIdx] != playerID {
		log.Debug().
			Str("player_id", playerID).
			Str("room_code", room.Code).
			Str("expected_player", func() string {
				if len(room.PlayerOrder) > 0 {
					return room.PlayerOrder[room.CurrentPlayerIdx]
				}
				return "none"
			}()).
			Msg("Invalid turn: player attempted roll out of turn")
		return
	}

	if room.RollsLeft <= 0 {
		log.Debug().
			Str("player_id", playerID).
			Str("room_code", room.Code).
			Msg("Invalid roll: no rolls left")
		return
	}

	// Convert held indices
	held := make(map[int]bool)
	for _, idx := range heldIndices {
		if i, ok := idx.(float64); ok {
			held[int(i)] = true
		}
	}

	// Roll non-held dice
	for i := 0; i < 5; i++ {
		if !held[i] {
			room.CurrentDice[i] = mrand.Intn(6) + 1
		}
	}
	room.RollsLeft--

	log.Debug().
		Str("player_id", playerID).
		Str("room_code", room.Code).
		Ints("dice", room.CurrentDice).
		Int("rolls_left", room.RollsLeft).
		Msg("Dice rolled")

	room.addEvent("ROLL_RESULT", map[string]interface{}{
		"player_id":  playerID,
		"dice":       room.CurrentDice,
		"rolls_left": room.RollsLeft,
	})
}

func (room *Room) handleCategoryChosen(event map[string]interface{}) {
	playerID, _ := event["player_id"].(string)
	category, _ := event["category"].(string)

	// Handle score as either float64 or int
	var score int
	switch v := event["score"].(type) {
	case float64:
		score = int(v)
	case int:
		score = v
	}

	// Validate turn
	if len(room.PlayerOrder) == 0 || room.PlayerOrder[room.CurrentPlayerIdx] != playerID {
		log.Debug().
			Str("player_id", playerID).
			Str("room_code", room.Code).
			Str("expected_player", func() string {
				if len(room.PlayerOrder) > 0 {
					return room.PlayerOrder[room.CurrentPlayerIdx]
				}
				return "none"
			}()).
			Msg("Invalid turn: player attempted to choose category out of turn")
		return
	}

	room.PlayerMutex.Lock()
	player, exists := room.Players[playerID]
	if !exists {
		room.PlayerMutex.Unlock()
		log.Warn().
			Str("player_id", playerID).
			Str("room_code", room.Code).
			Msg("Category chosen by non-existent player")
		return
	}

	// Check category not taken
	if _, taken := player.Scores[category]; taken {
		room.PlayerMutex.Unlock()
		log.Debug().
			Str("player_id", playerID).
			Str("room_code", room.Code).
			Str("category", category).
			Msg("Category already taken")
		return
	}

	player.Scores[category] = score
	player.TotalScore += score
	room.PlayerMutex.Unlock()

	log.Info().
		Str("player_id", playerID).
		Str("room_code", room.Code).
		Str("category", category).
		Int("score", score).
		Int("total_score", player.TotalScore).
		Msg("Score updated")

	room.addEvent("SCORE_UPDATE", map[string]interface{}{
		"player_id": playerID,
		"category":  category,
		"score":     score,
	})

	// Auto advance turn after scoring
	room.advanceTurn()

	// Check game end
	room.checkGameEnd()
}

func (room *Room) handleEndTurn(event map[string]interface{}) {
	playerID, _ := event["player_id"].(string)

	// Validate turn
	if len(room.PlayerOrder) == 0 || room.PlayerOrder[room.CurrentPlayerIdx] != playerID {
		return
	}

	room.advanceTurn()
}

func (room *Room) advanceTurn() {
	// Advance turn
	room.CurrentPlayerIdx = (room.CurrentPlayerIdx + 1) % len(room.PlayerOrder)
	room.RollsLeft = 3
	room.CurrentDice = []int{0, 0, 0, 0, 0}

	newPlayerID := room.PlayerOrder[room.CurrentPlayerIdx]
	log.Debug().
		Str("room_code", room.Code).
		Str("current_player", newPlayerID).
		Int("player_index", room.CurrentPlayerIdx).
		Msg("Turn advanced")

	room.addEvent("TURN_CHANGED", map[string]interface{}{
		"current_player": newPlayerID,
		"rolls_left":     3,
	})
}

func (room *Room) checkGameEnd() {
	room.PlayerMutex.RLock()
	defer room.PlayerMutex.RUnlock()

	// Check if all players have filled all categories
	for _, player := range room.Players {
		if player.IsViewer {
			continue // Skip viewers
		}
		if len(player.Scores) < len(Categories) {
			return
		}
	}

	// Calculate final scores with upper bonus
	finalScores := make(map[string]interface{})
	highestScore := -1
	var winners []string // Track multiple winners for draws

	for id, player := range room.Players {
		if player.IsViewer {
			continue // Skip viewers in scoring
		}

		upperTotal := 0
		for _, cat := range []string{"ones", "twos", "threes", "fours", "fives", "sixes"} {
			upperTotal += player.Scores[cat]
		}

		bonus := 0
		if upperTotal >= 63 {
			bonus = 35
		}
		finalTotal := player.TotalScore + bonus

		finalScores[id] = map[string]interface{}{
			"name":        player.Name,
			"base_score":  player.TotalScore,
			"upper_bonus": bonus,
			"final_score": finalTotal,
		}

		if finalTotal > highestScore {
			highestScore = finalTotal
			winners = []string{id}
		} else if finalTotal == highestScore {
			winners = append(winners, id)
		}
	}

	// Determine winner name (handle draws)
	winnerID := ""
	winnerName := ""
	isDraw := len(winners) > 1

	if len(winners) > 0 {
		winnerID = winners[0]
		if isDraw {
			// Build tied player names
			var names []string
			for _, wid := range winners {
				if p, exists := room.Players[wid]; exists {
					names = append(names, p.Name)
				}
			}
			winnerName = strings.Join(names, " & ") + " (TIE!)"
		} else if winner, exists := room.Players[winnerID]; exists {
			winnerName = winner.Name
		}
	}

	room.addEvent("GAME_END", map[string]interface{}{
		"final_scores": finalScores,
		"winner_id":    winnerID,
		"winner_name":  winnerName,
		"is_draw":      isDraw,
	})

	log.Info().
		Str("room_code", room.Code).
		Str("winner_id", winnerID).
		Str("winner_name", winnerName).
		Int("final_score", highestScore).
		Bool("is_draw", isDraw).
		Msg("Game ended")
}

// handlePlayerDisconnect handles when a player disconnects
func (gm *GameManager) handlePlayerDisconnect(room *Room, player *Player) {
	room.PlayerMutex.Lock()

	// Check if player was the host (use HostID, not PlayerOrder[0] which gets shuffled)
	isHost := room.HostID == player.ID
	gameStarted := room.GameStarted

	// Store player info for broadcast (before removing)
	playerName := player.Name
	playerID := player.ID

	// If game has started, keep player in room but mark as disconnected
	// This allows them to rejoin as a viewer later
	// Only remove completely if game hasn't started
	if !gameStarted {
		delete(room.Players, player.ID)
	} else {
		// Just close the connection, keep player data for rejoin
		player.ConnMutex.Lock()
		if player.Conn != nil {
			player.Conn.Close()
			player.Conn = nil
		}
		player.ConnMutex.Unlock()
		// Don't remove from Players map - allows rejoin
		// But we still need to handle turn order updates
	}

	// Check if the current player is leaving (before removing from order)
	wasCurrentPlayer := len(room.PlayerOrder) > 0 && room.CurrentPlayerIdx < len(room.PlayerOrder) && room.PlayerOrder[room.CurrentPlayerIdx] == player.ID

	// Find the index of the leaving player in the order (before removing)
	leavingPlayerIdx := -1
	for i, pid := range room.PlayerOrder {
		if pid == player.ID {
			leavingPlayerIdx = i
			break
		}
	}

	// Remove player from PlayerOrder (they can rejoin but won't be in turn order)
	newOrder := make([]string, 0, len(room.PlayerOrder))
	for _, pid := range room.PlayerOrder {
		if pid != player.ID {
			newOrder = append(newOrder, pid)
		}
	}
	room.PlayerOrder = newOrder

	// Update CurrentPlayerIdx if needed
	if wasCurrentPlayer && len(room.PlayerOrder) > 0 {
		// If current player left, advance to next player (same index, but array is shorter)
		room.CurrentPlayerIdx = room.CurrentPlayerIdx % len(room.PlayerOrder)
	} else if leavingPlayerIdx >= 0 && leavingPlayerIdx < room.CurrentPlayerIdx {
		// If a player BEFORE the current player left, decrement the index
		room.CurrentPlayerIdx--
	} else if room.CurrentPlayerIdx >= len(room.PlayerOrder) && len(room.PlayerOrder) > 0 {
		// Index out of bounds after removal, wrap around
		room.CurrentPlayerIdx = room.CurrentPlayerIdx % len(room.PlayerOrder)
	} else if len(room.PlayerOrder) == 0 {
		room.CurrentPlayerIdx = 0
	}

	// Count active players (not disconnected)
	remainingPlayers := 0
	for _, p := range room.Players {
		if p.Conn != nil {
			remainingPlayers++
		}
	}
	// If game hasn't started, use actual player count
	if !gameStarted {
		remainingPlayers = len(room.Players)
	}
	room.PlayerMutex.Unlock()

	// Broadcast PLAYER_LEFT event to remaining players (after unlocking)
	room.broadcast(map[string]interface{}{
		"type":        "PLAYER_LEFT",
		"player_id":   playerID,
		"player_name": playerName,
		"is_host":     isHost,
	}, playerID)

	// Only send TURN_CHANGED if the current player left (not just any player)
	if gameStarted && wasCurrentPlayer && len(room.PlayerOrder) > 0 {
		currentPlayerID := room.PlayerOrder[room.CurrentPlayerIdx]
		room.RollsLeft = 3
		room.CurrentDice = []int{0, 0, 0, 0, 0}

		room.addEvent("TURN_CHANGED", map[string]interface{}{
			"current_player": currentPlayerID,
			"rolls_left":     3,
		})

		log.Debug().
			Str("room_code", room.Code).
			Str("current_player", currentPlayerID).
			Int("player_index", room.CurrentPlayerIdx).
			Msg("Turn changed after current player disconnect")
	}

	// Check if host disconnected during game
	if isHost && gameStarted {
		log.Info().
			Str("room_code", room.Code).
			Str("player_id", playerID).
			Msg("Host disconnected during game, ending room")

		// Broadcast ROOM_ENDED event
		room.broadcastAll(map[string]interface{}{
			"type":   "ROOM_ENDED",
			"reason": "host_disconnected",
		})

		// Close all remaining player connections
		room.PlayerMutex.RLock()
		playersToClose := make([]*Player, 0, len(room.Players))
		for _, p := range room.Players {
			playersToClose = append(playersToClose, p)
		}
		room.PlayerMutex.RUnlock()

		for _, p := range playersToClose {
			p.ConnMutex.Lock()
			if p.Conn != nil {
				p.Conn.Close()
				p.Conn = nil
			}
			p.ConnMutex.Unlock()
		}

		// Remove room from manager
		gm.mutex.Lock()
		delete(gm.rooms, room.Code)
		gm.mutex.Unlock()
		return
	}

	// Check if only 1 player remains and game was started
	if remainingPlayers == 1 && gameStarted {
		log.Info().
			Str("room_code", room.Code).
			Int("remaining_players", remainingPlayers).
			Msg("Only 1 player remaining, ending room")

		// Broadcast ROOM_ENDED event
		room.broadcastAll(map[string]interface{}{
			"type":   "ROOM_ENDED",
			"reason": "insufficient_players",
		})

		// Close remaining player connection
		room.PlayerMutex.RLock()
		var remainingPlayer *Player
		for _, p := range room.Players {
			remainingPlayer = p
			break
		}
		room.PlayerMutex.RUnlock()

		if remainingPlayer != nil {
			remainingPlayer.ConnMutex.Lock()
			if remainingPlayer.Conn != nil {
				remainingPlayer.Conn.Close()
				remainingPlayer.Conn = nil
			}
			remainingPlayer.ConnMutex.Unlock()
		}

		// Remove room from manager
		gm.mutex.Lock()
		delete(gm.rooms, room.Code)
		gm.mutex.Unlock()
		return
	}

	log.Info().
		Str("room_code", room.Code).
		Str("player_id", playerID).
		Int("remaining_players", remainingPlayers).
		Msg("Player disconnected")
}
