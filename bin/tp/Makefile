.PHONY: build install test clean

BIN := tp
PREFIX ?= $(HOME)/.local

build:
	go build -o $(BIN) .

install: build
	@mkdir -p $(PREFIX)/bin
	@ln -sf $(CURDIR)/$(BIN) $(PREFIX)/bin/$(BIN)
	@echo "linked $(PREFIX)/bin/$(BIN) -> $(CURDIR)/$(BIN)"

test:
	go test ./...

clean:
	rm -f $(BIN)
