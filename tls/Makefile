all:
	@echo "use: make <target>"
	@echo ""
	@echo "where target is one of:"
	@echo ""
	@echo "  reinstall"
	@echo "  tests"
	@echo "  build-openssl-server | build-openssl-server-mac-102"
	@echo "  build-openssl-client | build-openssl-client-mac-102"

.PHONY: reinstall
reinstall:
	(cd core && cabal install --force-reinstalls --enable-tests && cd ../debug && cabal configure && cabal build && cabal install --force-reinstalls)

.PHONY: tests
tests: test-scripts/TestClient
	stack exec TestClient with-local

.PHONY: travis-tests
travis-tests: test-scripts/TestClient
	stack exec TestClient

.PHONY: build-openssl-server
build-openssl-server:
	gcc -Wall -o test-scripts/openssl-server -Wno-deprecated-declarations test-scripts/openssl-server.c -lcrypto -lssl

# for building on osx with the latest openssl version in brew
.PHONY: build-openssl-server-mac-102
build-openssl-server-mac-102:
	gcc -Wall -o test-scripts/openssl-server \
			-L/usr/local/opt/openssl/lib \
			-I/usr/local/opt/openssl/include \
			-lcrypto -lssl test-scripts/openssl-server.c

.PHONY: build-openssl-client
build-openssl-client:
	gcc -Wall -o test-scripts/openssl-client -Wno-deprecated-declarations test-scripts/openssl-client.c -lcrypto -lssl

# for building on osx with the latest openssl version in brew
.PHONY: build-openssl-client-mac-102
build-openssl-client-mac-102:
	gcc -Wall -o test-scripts/openssl-client \
			-L/usr/local/opt/openssl/lib \
			-I/usr/local/opt/openssl/include \
			-lcrypto -lssl test-scripts/openssl-client.c
