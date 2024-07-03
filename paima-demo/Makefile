godot-website:
	cd web-server && python3 serve.py -n -p 8060 --root ./godot-web-export

# # Serve original frontend from "open-world" template
# original-frontend-website:
# 	cd web-server && python3 serve.py -n -p 8061 --root ../open-world/frontend

init:
	./paima-engine init template open-world && cd open-world && npm run initialize 

replace-env-file:
	cp .env.localhost.godot .env.localhost

paima-middleware:
	cd open-world && npm install && npm run pack && npm run pack:middleware

init-batcher:
	./paima-engine batcher && sudo chmod +x ./batcher/start.sh && cp .env.localhost ./batcher/.env.localhost

webserver-dir:
	mkdir -p web-server/godot-web-export/paima

distribute-middleware:
	cp ./open-world/middleware/packaged/middleware.js ./open-world/frontend/paimaMiddleware.js \
	&& cp -r ./open-world/middleware/packaged/middleware.js ./web-server/godot-web-export/paima/paimaMiddleware.js

start-db:
	cd open-world && npm run database:up

start-chain:
	cd open-world && npm run chain:start

deploy-contracts:
	cd open-world && npm run chain:deploy

reset-db:
	cd open-world && npm run database:reset

start-paima-node:
	NETWORK=localhost ./paima-engine run

start-batcher:
	cd batcher && NETWORK=localhost ./start.sh

