image-name="molamk/node-app"

build:
	docker build -t $(image-name) .

run:
	docker run -p 3000:80 -d $(image-name)

tag:
	docker tag molamk/node-app molamk/node-app:latest

push:
	docker push molamk/node-app
