# Yahtzee Online (Godot 4)

A cross-platform, multiplayer Yahtzee clone built with **Godot 4.5**.

## Features

- 2-6 player multiplayer
- Multiple network modes:
  - **Online Server** - connect via HTTP to the Go backend
  - **Practice (vs Bots)** - play offline against AI opponents
- Beautiful dice with dot graphics and roll animations
- Full Yahtzee scoring with upper bonus and Yahtzee bonus
- Game end detection and winner display
- Interactive scorecard with category previews
- In-game chat
- Docker deployment for the Go server

## Quick Start

### Running the Godot Client

1. Open the project in **Godot 4.5+**
2. Press **▶ (Play)** to run
3. Select **"Practice (vs Bots)"** mode to play immediately without a server

### Running the Go Server

```bash

# Build and run locally

cd server
go mod tidy
go run .

# Or with Docker Compose

docker compose up --build
```

The server runs on port `8080` by default.

## Network Modes

### 1. Online Server

Connect to the Go backend via HTTP.

- Create or join rooms with room codes
- All game logic validated server-side

### 2. Practice (vs Bots)

Play offline against AI opponents.

- No server required
- Great for learning the game

## Server Configuration

The default server URL is configured in `autoload/GameConfig.gd`:

```gdscript
var server_url: String = "<https://games.macco.dev/api/v1/g/yahtzee>"
```

### Server API Endpoints

| Method | Endpoint | Description |
|--|-|-|
| GET | `/health` | Health check |
| POST | `/rooms` | Create a new room |
| POST | `/rooms/join` | Join existing room |
| POST | `/rooms/{code}/events` | Send game event |
| GET | `/rooms/{code}/events?since=N&token=T` | Long-poll for events |

## Development

### Prerequisites

- Godot 4.5+
- Go 1.21+ (for server)
- Docker (optional, for deployment)

### Running Tests

```bash

# Server tests

cd server
go test ./...
```

## Docker Deployment

```bash

# Build and run

docker compose up --build -d

# View logs

docker compose logs -f

# Stop

docker compose down
```

The server includes:

- Automatic room cleanup (30-minute timeout)
- Health check endpoint
- CORS configuration for web clients

## Credits

- Engine: [Godot 4](https://godotengine.org/)
- HTTP Router: [chi](https://github.com/go-chi/chi)
