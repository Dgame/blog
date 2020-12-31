env:
	cp .env.dist .env
new: kill
	docker-compose up -d --build --remove-orphans
up:
	docker-compose up -d
kill:
	docker-compose kill
	docker-compose down --volumes --remove-orphans
restart:
	docker-compose restart