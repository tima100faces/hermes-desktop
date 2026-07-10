# Auto-test pipeline run by agents
# Usage: make test-all API_KEY=xxx

test-all: test test-integration
	@echo "✅ All tests complete"

test-integration:
	@echo "🔍 Running integration tests against Hermes API..."
	@API_KEY=$(API_KEY) ./scripts/test-integration.sh