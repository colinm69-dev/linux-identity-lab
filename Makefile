.PHONY: up verify shell logs down reset

up:
	docker compose up -d --build --wait

verify:
	./scripts/verify.sh

shell:
	docker compose exec client bash

logs:
	docker compose logs --tail=100

down:
	docker compose down

reset:
	docker compose down -v
