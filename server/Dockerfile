FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY go.mod go.sum* ./
RUN go mod download

COPY *.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o /yahtzee-server

FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /

COPY --from=builder /yahtzee-server /yahtzee-server

EXPOSE 8080

ENV PORT=8080

CMD ["/yahtzee-server"]
