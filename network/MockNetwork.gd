class_name MockNetwork
extends Node

## Mock network for offline testing - simulates server authority locally

signal game_event_received(event: Dictionary)
signal connection_state_changed(state: int, error: int)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, ERROR }

var state: ConnectionState = ConnectionState.DISCONNECTED
var local_player_id: String = ""
var local_player_name: String = ""
var is_host: bool = true

# Game authority state (same as LocalNetwork)
var game_started: bool = false
var current_player_index: int = 0
var turn_order: Array[String] = []
var player_dice: Dictionary = {}  # player_id -> Array[int]
var rolls_left: Dictionary = {}    # player_id -> int
var player_scores: Dictionary = {} # player_id -> Dictionary (category -> score)
var player_used_categories: Dictionary = {}  # player_id -> Array[String]
var yahtzee_bonuses: Dictionary = {}  # player_id -> int
var players: Dictionary = {}  # player_id -> player_name

# Mock players for testing
var mock_opponents: Array[Dictionary] = []
var opponent_turn_timer: Timer


func _ready() -> void:
	opponent_turn_timer = Timer.new()
	opponent_turn_timer.one_shot = true
	opponent_turn_timer.timeout.connect(_on_opponent_turn_timer)
	add_child(opponent_turn_timer)


func connect_to_match(_params: Dictionary) -> void:
	# Immediately connected in mock mode
	state = ConnectionState.CONNECTED
	local_player_id = "mock_player_" + str(randi() % 10000)
	local_player_name = GameConfig.player_name if GameConfig.player_name != "" else "Player"
	
	get_node("/root/Logger").info("Connecting to mock match", {
		"player_name": local_player_name,
		"function": "connect_to_match"
	})
	
	# Add local player
	players[local_player_id] = local_player_name
	player_dice[local_player_id] = [0, 0, 0, 0, 0]
	rolls_left[local_player_id] = 3
	player_scores[local_player_id] = {}
	player_used_categories[local_player_id] = []
	yahtzee_bonuses[local_player_id] = 0
	turn_order.append(local_player_id)
	
	# Add mock opponents based on GameConfig
	var opponent_count: int = GameConfig.max_players - 1
	for i in range(opponent_count):
		var opp_id: String = "mock_opponent_" + str(i)
		var opp_name: String = "Bot " + str(i + 1)
		players[opp_id] = opp_name
		player_dice[opp_id] = [0, 0, 0, 0, 0]
		rolls_left[opp_id] = 3
		player_scores[opp_id] = {}
		player_used_categories[opp_id] = []
		yahtzee_bonuses[opp_id] = 0
		turn_order.append(opp_id)
		mock_opponents.append({"id": opp_id, "name": opp_name})
	
	get_node("/root/Logger").info("Mock match connected", {
		"player_id": local_player_id,
		"player_count": players.size(),
		"opponent_count": opponent_count,
		"function": "connect_to_match"
	})
	
	connection_state_changed.emit(ConnectionState.CONNECTED, 0)
	
	# Emit player joined events
	for pid in players:
		_emit_event({
			"type": "PLAYER_JOINED",
			"player_id": pid,
			"player_name": players[pid],
			"is_host": pid == local_player_id
		})


func disconnect_from_match() -> void:
	get_node("/root/Logger").info("Disconnecting from mock match", {
		"player_id": local_player_id,
		"function": "disconnect_from_match"
	})
	state = ConnectionState.DISCONNECTED
	game_started = false
	players.clear()
	turn_order.clear()
	player_dice.clear()
	rolls_left.clear()
	player_scores.clear()
	player_used_categories.clear()
	yahtzee_bonuses.clear()
	mock_opponents.clear()
	connection_state_changed.emit(ConnectionState.DISCONNECTED, 0)


func send_game_event(event: Dictionary) -> void:
	if state != ConnectionState.CONNECTED:
		get_node("/root/Logger").warn("Cannot send event: not connected", {
			"event_type": str(event.get("type", "")),
			"function": "send_game_event"
		})
		return
	
	var event_type: String = event.get("type", "")
	
	get_node("/root/Logger").debug("Sending game event (mock)", {
		"event_type": event_type,
		"player_id": local_player_id,
		"function": "send_game_event"
	})
	
	match event_type:
		"START_GAME":
			_handle_start_game()
		"REQUEST_ROLL":
			_handle_request_roll(event)
		"CATEGORY_CHOSEN":
			_handle_category_chosen(event)
		"REQUEST_END_TURN":
			_handle_end_turn(event)
		"CHAT_MESSAGE":
			_emit_event({
				"type": "CHAT_MESSAGE",
				"player_id": local_player_id,
				"player_name": local_player_name,
				"message": event.get("message", "")
			})


func _handle_start_game() -> void:
	if game_started:
		get_node("/root/Logger").warn("Game already started", {"function": "_handle_start_game"})
		return
	
	game_started = true
	
	# Shuffle turn order randomly
	var shuffled_order: Array[String] = []
	for pid in turn_order:
		shuffled_order.append(pid)
	shuffled_order.shuffle()
	turn_order = shuffled_order
	current_player_index = 0
	
	# Reset game state
	for pid in players:
		player_dice[pid] = [0, 0, 0, 0, 0]
		rolls_left[pid] = 3
		player_scores[pid] = {}
		player_used_categories[pid] = []
		yahtzee_bonuses[pid] = 0
	
	# Build players data for the event
	var players_data: Dictionary = {}
	var player_list: Array = []
	for pid in players:
		var pdata := {
			"player_id": pid,
			"name": players[pid],
			"total_score": 0
		}
		players_data[pid] = pdata
		player_list.append(pdata)
	
	get_node("/root/Logger").info("Game started (mock)", {
		"player_count": players.size(),
		"turn_order": turn_order,
		"first_player": turn_order[0],
		"function": "_handle_start_game"
	})
	
	_emit_event({
		"type": "GAME_STARTED",
		"players": players_data,
		"player_list": player_list,
		"turn_order": turn_order,
		"current_player": turn_order[0]
	})


func start_first_bot_turn() -> void:
	## Called by GameTable after UI animation completes to start bot's turn if needed
	if not game_started:
		return
	var first_player: String = turn_order[current_player_index]
	if first_player != local_player_id:
		opponent_turn_timer.start(0.5)


func _handle_request_roll(event: Dictionary) -> void:
	var player_id: String = local_player_id  # Only local player can request in mock
	var current_player: String = turn_order[current_player_index]
	
	if player_id != current_player:
		get_node("/root/Logger").debug("Roll request ignored: not player's turn", {
			"player_id": player_id,
			"current_player": current_player,
			"function": "_handle_request_roll"
		})
		return
	
	if rolls_left.get(player_id, 0) <= 0:
		get_node("/root/Logger").debug("Roll request ignored: no rolls left", {
			"player_id": player_id,
			"function": "_handle_request_roll"
		})
		return
	
	var held: Array = event.get("held_indices", event.get("held_dice", []))
	var current_dice: Array = player_dice.get(player_id, [0, 0, 0, 0, 0])
	var new_dice: Array[int] = []
	
	for i in range(5):
		if i in held:
			new_dice.append(current_dice[i] if i < current_dice.size() else _roll_die())
		else:
			new_dice.append(_roll_die())
	
	player_dice[player_id] = new_dice
	rolls_left[player_id] = rolls_left.get(player_id, 3) - 1
	
	get_node("/root/Logger").debug("Dice rolled", {
		"player_id": player_id,
		"dice": new_dice,
		"rolls_left": rolls_left[player_id],
		"held_count": held.size(),
		"function": "_handle_request_roll"
	})
	
	_emit_event({
		"type": "ROLL_RESULT",
		"player_id": player_id,
		"dice": new_dice,
		"rolls_left": rolls_left[player_id]
	})


func _handle_category_chosen(event: Dictionary) -> void:
	var player_id: String = local_player_id
	var current_player: String = turn_order[current_player_index]
	
	if player_id != current_player:
		get_node("/root/Logger").debug("Category choice ignored: not player's turn", {
			"player_id": player_id,
			"current_player": current_player,
			"function": "_handle_category_chosen"
		})
		return
	
	var category: String = event.get("category", "")
	var used: Array = player_used_categories.get(player_id, [])
	
	if category in used:
		get_node("/root/Logger").warn("Category already used", {
			"player_id": player_id,
			"category": category,
			"function": "_handle_category_chosen"
		})
		return
	
	var dice: Array = player_dice.get(player_id, [0, 0, 0, 0, 0])
	var int_dice: Array[int] = []
	for d in dice:
		int_dice.append(int(d))
	var all_scores: Dictionary = ScoreLogic.score_all(int_dice)
	var score: int = int(all_scores.get(category, 0))
	
	# Yahtzee bonus check
	var yahtzee_bonus_added := false
	if _is_yahtzee(dice):
		if "yahtzee" in used and player_scores.get(player_id, {}).get("yahtzee", 0) > 0:
			yahtzee_bonuses[player_id] = yahtzee_bonuses.get(player_id, 0) + 100
			yahtzee_bonus_added = true
	
	# Store score
	if not player_scores.has(player_id):
		player_scores[player_id] = {}
	player_scores[player_id][category] = score
	used.append(category)
	player_used_categories[player_id] = used
	
	# Calculate upper bonus
	var upper_bonus: int = _calculate_upper_bonus(player_id)
	
	get_node("/root/Logger").info("Category chosen", {
		"player_id": player_id,
		"category": category,
		"score": score,
		"upper_bonus": upper_bonus,
		"yahtzee_bonus": yahtzee_bonuses.get(player_id, 0),
		"yahtzee_bonus_added": yahtzee_bonus_added,
		"function": "_handle_category_chosen"
	})
	
	_emit_event({
		"type": "SCORE_UPDATE",
		"player_id": player_id,
		"category": category,
		"score": score,
		"upper_bonus": upper_bonus,
		"yahtzee_bonus": yahtzee_bonuses.get(player_id, 0)
	})
	
	# Auto end turn after scoring
	_advance_turn()


func _handle_end_turn(_event: Dictionary) -> void:
	_advance_turn()


func _advance_turn() -> void:
	# Check for game end
	if _check_game_end():
		get_node("/root/Logger").info("Game end condition met", {"function": "_advance_turn"})
		_emit_game_end()
		return
	
	# Safety check: ensure turn_order has elements
	if turn_order.is_empty():
		get_node("/root/Logger").warn("Cannot advance turn: turn_order is empty", {
			"function": "_advance_turn"
		})
		return
	
	# Move to next player
	current_player_index = (current_player_index + 1) % turn_order.size()
	var next_player: String = turn_order[current_player_index]
	
	# Reset dice for next player
	player_dice[next_player] = [0, 0, 0, 0, 0]
	rolls_left[next_player] = 3
	
	get_node("/root/Logger").info("Turn advanced", {
		"next_player": next_player,
		"player_name": players.get(next_player, "Unknown"),
		"is_bot": next_player != local_player_id,
		"function": "_advance_turn"
	})
	
	_emit_event({
		"type": "TURN_CHANGED",
		"current_player": next_player,
		"rolls_left": 3
	})
	
	# If it's a bot's turn, simulate their play
	if next_player != local_player_id:
		get_node("/root/Logger").debug("Starting bot turn simulation", {
			"bot_id": next_player,
			"function": "_advance_turn"
		})
		opponent_turn_timer.start(1.5)


func _on_opponent_turn_timer() -> void:
	# Safety check: ensure turn_order has elements and current_player_index is valid
	if turn_order.is_empty():
		get_node("/root/Logger").warn("Cannot process bot turn: turn_order is empty", {
			"function": "_on_opponent_turn_timer"
		})
		return
	
	if current_player_index < 0 or current_player_index >= turn_order.size():
		get_node("/root/Logger").warn("Invalid current_player_index", {
			"current_player_index": current_player_index,
			"turn_order_size": turn_order.size(),
			"function": "_on_opponent_turn_timer"
		})
		# Reset to valid index
		current_player_index = 0
		if turn_order.is_empty():
			return
	
	var current_player: String = turn_order[current_player_index]
	if current_player == local_player_id:
		return
	
	# Simulate bot rolling - await to ensure turn completes before advancing
	await _simulate_bot_roll(current_player)


func _simulate_bot_roll(bot_id: String) -> void:
	# Start bot's turn with first roll
	await _bot_turn_loop(bot_id)


func _bot_turn_loop(bot_id: String) -> void:
	var rolls_remaining: int = 3
	var current_dice: Array[int] = []
	var used: Array = player_used_categories.get(bot_id, [])
	
	# First roll - roll all dice
	current_dice = []
	for i in range(5):
		current_dice.append(_roll_die())
	rolls_remaining -= 1
	
	player_dice[bot_id] = current_dice
	rolls_left[bot_id] = rolls_remaining
	
	get_node("/root/Logger").debug("Bot rolled dice (roll 1)", {
		"bot_id": bot_id,
		"bot_name": players.get(bot_id, "Unknown"),
		"dice": current_dice,
		"rolls_left": rolls_remaining,
		"function": "_bot_turn_loop"
	})
	
	# Emit first roll result (no dice held yet)
	_emit_event({
		"type": "ROLL_RESULT",
		"player_id": bot_id,
		"dice": current_dice,
		"rolls_left": rolls_remaining,
		"held_indices": []
	})
	
	await get_tree().create_timer(1.0).timeout
	
	# Loop for up to 3 rolls
	while rolls_remaining > 0:
		# Evaluate current dice and decide: roll again or choose category
		var decision: Dictionary = _bot_decide_action(bot_id, current_dice, rolls_remaining, used)
		
		if decision.should_choose_category:
			# Choose category and end turn - await to ensure category is chosen before returning
			await _bot_choose_category(bot_id, decision.category, current_dice)
			return
		
		# Show which dice bot is holding (for next roll)
		var held_indices: Array[int] = decision.held_indices
		
		# Emit roll result showing current dice and which will be held
		_emit_event({
			"type": "ROLL_RESULT",
			"player_id": bot_id,
			"dice": current_dice,
			"rolls_left": rolls_remaining,
			"held_indices": held_indices
		})
		
		await get_tree().create_timer(1.2).timeout  # Pause to show held dice
		
		# Roll again with optimal holds
		current_dice = _bot_roll_with_holds(current_dice, held_indices)
		rolls_remaining -= 1
		player_dice[bot_id] = current_dice
		rolls_left[bot_id] = rolls_remaining
		
		get_node("/root/Logger").debug("Bot rolled dice (roll %d)" % (3 - rolls_remaining + 1), {
			"bot_id": bot_id,
			"bot_name": players.get(bot_id, "Unknown"),
			"dice": current_dice,
			"held_indices": held_indices,
			"rolls_left": rolls_remaining,
			"function": "_bot_turn_loop"
		})
		
		# Emit final roll result (no more rolls, so no held dice)
		if rolls_remaining == 0:
			_emit_event({
				"type": "ROLL_RESULT",
				"player_id": bot_id,
				"dice": current_dice,
				"rolls_left": 0,
				"held_indices": []
			})
			await get_tree().create_timer(1.0).timeout
	
	# After 3 rolls, must choose a category - await to ensure category is chosen
	var final_decision: Dictionary = _bot_decide_action(bot_id, current_dice, 0, used)
	await _bot_choose_category(bot_id, final_decision.category, current_dice)


func _bot_roll_with_holds(current_dice: Array[int], held_indices: Array[int]) -> Array[int]:
	var new_dice: Array[int] = []
	for i in range(5):
		if i in held_indices:
			new_dice.append(current_dice[i])
		else:
			new_dice.append(_roll_die())
	return new_dice


func _bot_decide_action(bot_id: String, dice: Array[int], rolls_left: int, used_categories: Array) -> Dictionary:
	# Calculate current best score
	var scores: Dictionary = ScoreLogic.score_all(dice)
	var best_category: String = ""
	var best_score: int = -1
	var best_strategic_value: float = -1.0
	
	# Evaluate each available category
	for cat in ScoreLogic.CATEGORIES:
		if cat in used_categories:
			continue
		var score: int = int(scores.get(cat, 0))
		var strategic_value: float = _bot_calculate_strategic_value(bot_id, cat, score, used_categories)
		
		if strategic_value > best_strategic_value:
			best_strategic_value = strategic_value
			best_score = score
			best_category = cat
	
	# If no category found, pick first available (shouldn't happen)
	if best_category == "":
		for cat in ScoreLogic.CATEGORIES:
			if cat not in used_categories:
				best_category = cat
				best_score = int(scores.get(cat, 0))
				break
	
	# Decide whether to roll again or choose category
	var should_choose: bool = false
	
	if rolls_left == 0:
		# Must choose after 3 rolls
		should_choose = true
	elif best_score >= 25:
		# Good score (full house or better) - take it if rolls left <= 1
		should_choose = rolls_left <= 1
	elif best_score >= 15 and rolls_left == 1:
		# Decent score on last roll - take it
		should_choose = true
	elif best_score == 0 and rolls_left <= 1:
		# No good options, might as well take something on last roll
		should_choose = true
	else:
		# Roll again to try for better score
		should_choose = false
	
	var held_indices: Array[int] = []
	if not should_choose:
		held_indices = _bot_decide_holds(bot_id, dice, used_categories, rolls_left)
	
	return {
		"should_choose_category": should_choose,
		"category": best_category,
		"score": best_score,
		"held_indices": held_indices
	}


func _bot_get_unique_sorted(dice: Array[int]) -> Array[int]:
	var seen: Dictionary = {}
	var result: Array[int] = []
	for d in dice:
		if not seen.has(d):
			seen[d] = true
			result.append(d)
	result.sort()
	return result


func _bot_decide_holds(bot_id: String, dice: Array[int], used_categories: Array, rolls_left: int) -> Array[int]:
	# Strategy: hold dice that contribute to high-value categories
	var counts: Dictionary = ScoreLogic.count_faces(dice)
	var held: Array[int] = []
	
	# Priority 1: Hold dice for Yahtzee (5 of a kind)
	var max_count: int = 0
	var max_face: int = 0
	for face in counts:
		var count: int = counts[face]
		if count > max_count:
			max_count = count
			max_face = face
	
	if max_count >= 3:
		# Hold all dice of this face
		for i in range(5):
			if dice[i] == max_face:
				held.append(i)
		return held
	
	# Priority 2: Hold for large straight
	if ScoreLogic.is_large_straight(dice):
		# Already have large straight, hold all
		return [0, 1, 2, 3, 4]
	
	var unique: Array[int] = _bot_get_unique_sorted(dice)
	# Check if we're close to large straight
	var straight_candidates := [[1,2,3,4,5], [2,3,4,5,6]]
	for candidate in straight_candidates:
		var matches: int = 0
		for val in candidate:
			if val in unique:
				matches += 1
		if matches >= 4:
			# Hold dice that are part of the straight
			for i in range(5):
				if dice[i] in candidate:
					held.append(i)
			return held
	
	# Priority 3: Hold for full house (3 of one, 2 of another)
	if max_count >= 2:
		# Hold the pair/triple
		for i in range(5):
			if dice[i] == max_face:
				held.append(i)
		
		# Also hold a pair of another face if exists
		for face in counts:
			if face != max_face and counts[face] >= 2:
				for i in range(5):
					if dice[i] == face and i not in held:
						held.append(i)
						if held.size() >= 5:
							break
				break
		
		if held.size() >= 3:
			return held
	
	# Priority 4: Hold for small straight
	var small_straight_candidates := [[1,2,3,4], [2,3,4,5], [3,4,5,6]]
	for candidate in small_straight_candidates:
		var matches: int = 0
		for val in candidate:
			if val in unique:
				matches += 1
		if matches >= 3:
			# Hold dice that are part of the straight
			for i in range(5):
				if dice[i] in candidate:
					held.append(i)
			return held
	
	# Priority 5: Hold high pairs (for three/four of a kind)
	if max_count >= 2:
		for i in range(5):
			if dice[i] == max_face:
				held.append(i)
		return held
	
	# Priority 6: Hold high single dice (for upper section or three/four of a kind)
	# Hold dice >= 4
	for i in range(5):
		if dice[i] >= 4:
			held.append(i)
	
	return held


func _bot_calculate_strategic_value(bot_id: String, category: String, score: int, used_categories: Array) -> float:
	var strategic_value: float = float(score)
	var scores: Dictionary = player_scores.get(bot_id, {})
	
	# Boost upper section categories if close to bonus
	if category in ["ones", "twos", "threes", "fours", "fives", "sixes"]:
		var upper_total: int = 0
		for cat in ["ones", "twos", "threes", "fours", "fives", "sixes"]:
			upper_total += scores.get(cat, 0)
		
		if upper_total + score >= 63:
			# This would get the bonus - add bonus value
			strategic_value += 35.0
		elif upper_total + score >= 50:
			# Close to bonus - add some value
			strategic_value += 10.0
	
	# Boost Yahtzee significantly
	if category == "yahtzee" and score > 0:
		strategic_value += 20.0
	
	# Boost high-value lower section categories
	if category == "large_straight" and score > 0:
		strategic_value += 5.0
	elif category == "full_house" and score > 0:
		strategic_value += 3.0
	
	# Penalize zero scores slightly (but not too much - might be forced)
	if score == 0:
		strategic_value -= 1.0
	
	return strategic_value


func _bot_choose_category(bot_id: String, category: String, dice: Array[int]) -> void:
	var used: Array = player_used_categories.get(bot_id, [])
	var scores: Dictionary = ScoreLogic.score_all(dice)
	var score: int = int(scores.get(category, 0))
	
	# Yahtzee bonus check
	var yahtzee_bonus_added := false
	if _is_yahtzee(dice):
		if "yahtzee" in used and player_scores.get(bot_id, {}).get("yahtzee", 0) > 0:
			yahtzee_bonuses[bot_id] = yahtzee_bonuses.get(bot_id, 0) + 100
			yahtzee_bonus_added = true
	
	# Store score
	if not player_scores.has(bot_id):
		player_scores[bot_id] = {}
	player_scores[bot_id][category] = score
	used.append(category)
	player_used_categories[bot_id] = used
	
	var upper_bonus: int = _calculate_upper_bonus(bot_id)
	
	get_node("/root/Logger").info("Bot chose category", {
		"bot_id": bot_id,
		"bot_name": players.get(bot_id, "Unknown"),
		"category": category,
		"score": score,
		"upper_bonus": upper_bonus,
		"function": "_bot_choose_category"
	})
	
	_emit_event({
		"type": "SCORE_UPDATE",
		"player_id": bot_id,
		"category": category,
		"score": score,
		"upper_bonus": upper_bonus,
		"yahtzee_bonus": yahtzee_bonuses.get(bot_id, 0)
	})
	
	# End bot's turn
	await get_tree().create_timer(0.5).timeout
	_advance_turn()


func _roll_die() -> int:
	return randi_range(1, 6)


func _is_yahtzee(dice: Array) -> bool:
	if dice.size() != 5:
		return false
	var first: int = dice[0]
	for d in dice:
		if d != first:
			return false
	return true


func _calculate_upper_bonus(player_id: String) -> int:
	var upper_categories: Array[String] = ["ones", "twos", "threes", "fours", "fives", "sixes"]
	var upper_total: int = 0
	var scores: Dictionary = player_scores.get(player_id, {})
	
	for cat in upper_categories:
		upper_total += scores.get(cat, 0)
	
	if upper_total >= 63:
		return 35
	return 0


func _check_game_end() -> bool:
	var total_categories := ScoreLogic.CATEGORIES.size()  # 12 categories
	for pid in players:
		var used: Array = player_used_categories.get(pid, [])
		if used.size() < total_categories:
			return false
	return true


func _emit_game_end() -> void:
	game_started = false
	
	# Build final scores in the format expected by GameTable
	var final_scores: Dictionary = {}
	var highest_score: int = -1
	var winners: Array[String] = []  # Track multiple winners for draw
	
	for pid in players:
		var scores: Dictionary = player_scores.get(pid, {})
		var base_total: int = 0
		for cat in scores:
			base_total += scores[cat]
		
		var upper_bonus: int = _calculate_upper_bonus(pid)
		var yahtzee_bonus: int = yahtzee_bonuses.get(pid, 0)
		var final_total: int = base_total + upper_bonus + yahtzee_bonus
		
		# Store in format expected by GameTable._show_game_end_overlay
		final_scores[pid] = {
			"name": players.get(pid, "Unknown"),
			"base_score": base_total,
			"upper_bonus": upper_bonus,
			"yahtzee_bonus": yahtzee_bonus,
			"final_score": final_total
		}
		
		# Track winner(s) - handle draws
		if final_total > highest_score:
			highest_score = final_total
			winners.clear()
			winners.append(pid)
		elif final_total == highest_score:
			winners.append(pid)
	
	# Determine winner name (handle draws)
	var winner_id: String = winners[0] if winners.size() > 0 else ""
	var winner_name: String = ""
	if winners.size() > 1:
		# It's a draw - list all tied players
		var names: Array[String] = []
		for pid in winners:
			names.append(players.get(pid, "Unknown"))
		winner_name = " & ".join(names) + " (TIE!)"
	else:
		winner_name = players.get(winner_id, "Unknown")
	
	get_node("/root/Logger").info("Game ended", {
		"winner_id": winner_id,
		"winner_name": winner_name,
		"is_draw": winners.size() > 1,
		"highest_score": highest_score,
		"function": "_emit_game_end"
	})
	
	_emit_event({
		"type": "GAME_END",
		"final_scores": final_scores,
		"winner_id": winner_id,
		"winner_name": winner_name,
		"is_draw": winners.size() > 1
	})


func _emit_event(event: Dictionary) -> void:
	# Use call_deferred to avoid issues with signal emission during processing
	call_deferred("_do_emit_event", event)


func _do_emit_event(event: Dictionary) -> void:
	game_event_received.emit(event)


func get_local_player_id() -> String:
	return local_player_id


func is_connected_to_server() -> bool:
	return state == ConnectionState.CONNECTED
