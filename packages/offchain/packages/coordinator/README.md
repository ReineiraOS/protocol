# @reineira-os/coordinator

CCTP message distribution service for Reineira operator network.

## Overview

The coordinator service receives CCTP transaction notifications and distributes them to subscribed operators for execution. Uses round-robin selection with SSE streaming.

## Running

```bash
# Development
npm run start:dev

# Production
npm run build && npm run start:prod
```

Default port: `3001`

## API Endpoints

### Submit Transaction

**POST /bridges/cctp/transactions**

Submit a CCTP burn transaction for relay distribution.

```bash
curl -X POST http://localhost:3001/bridges/cctp/transactions \
  -H "Content-Type: application/json" \
  -d '{"transactionHash": "0x1234...64chars", "sourceChainId": 11155111}'
```

Response (202):

```json
{
  "id": "uuid",
  "status": "queued",
  "message": "CCTP transaction queued for relay"
}
```

### Subscribe to Relay Events (SSE)

**GET /operators/:address/subscribe**

Operators subscribe to receive assigned transactions via Server-Sent Events.

```bash
curl -N http://localhost:3001/operators/0x1234.../subscribe
```

Events:

```
event: relay
id: <message-id>
data: {"id":"...","transactionHash":"0x...","sourceChainId":11155111,"taskType":"0x7f59...","createdAt":"..."}
```

### Operator Stats

**GET /operators/stats**

```bash
curl http://localhost:3001/operators/stats
```

```json
{
  "subscribedCount": 3,
  "operators": ["0x1234...", "0xabcd...", "0x5678..."]
}
```

### OpenAPI Spec

- JSON: `GET /api/openapi.json`
- YAML: `GET /api/openapi.yaml`

## Architecture

```
src/
├── domain/              # Core entities and value objects
│   ├── entities/        # RelayMessage
│   └── value-objects/   # ChainId, TransactionHash
├── application/         # Business logic
│   ├── dto/             # Request/response DTOs
│   └── services/        # CoordinatorService
├── infrastructure/      # External concerns
│   └── repositories/    # MessageRepository (in-memory)
└── interfaces/          # API layer
    ├── http/            # REST controllers
    └── sse/             # SSE controllers
```

## Configuration

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `PORT`   | `3001`  | HTTP port   |

## Testing

```bash
# Unit tests
npm run test

# E2E tests
npm run test:e2e

# Coverage
npm run test:cov
```

## Future Work

- **Webhook Integration**: Replace HTTP submission with QuickNode webhooks
- **Reputation Selection**: Use `OperatorRegistry.selectOperator()` contract method
- **Persistent Storage**: Replace in-memory repository with PostgreSQL/Redis
- **Message Acknowledgment**: Add retry mechanism for failed deliveries

## License

MIT
