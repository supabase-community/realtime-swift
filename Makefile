test-all: test-swift test-linux

test-swift:
	swift test --parallel

test-linux:
	docker run \
		--rm \
		-v "$(PWD):$(PWD)" \
		-w "$(PWD)" \
		swift:5.5 \
		bash -c 'make test-swift'

format:
	swift format --in-place --recursive .


.PHONY: test-swift test-linux format
