start:
	export NGINX_TYPE=oss && docker-compose -f tests/docker/docker-compose.yml up -d

start-plus:
	export NGINX_TYPE=plus && docker-compose -f tests/docker/docker-compose.yml up -d

test:
	export NGINX_TYPE=oss && bash tests/test.sh --type oss

test-plus:
	export NGINX_TYPE=plus && bash tests/test.sh --type plus

down:
	docker-compose -f tests/docker/docker-compose.yml down

clean: 
	docker kill $$(docker ps -q) 2> /dev/null || true
	docker system prune -a
