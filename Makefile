P4C ?= p4c-bm2-ss
P4FLAGS ?= --p4v 16 --Werror
SOURCE := p4src/main.p4
BUILD_DIR := build
BMV2_JSON := $(BUILD_DIR)/switch.json
P4INFO := $(BUILD_DIR)/switch.p4info.txtpb

.PHONY: all compile test clean

all: compile

compile: $(BMV2_JSON) $(P4INFO)

$(BMV2_JSON) $(P4INFO): $(SOURCE) $(wildcard p4src/include/*.p4)
	mkdir -p $(BUILD_DIR)
	$(P4C) $(P4FLAGS) --p4runtime-files $(P4INFO) -o $(BMV2_JSON) $(SOURCE)

test: compile
	bash tests/check_contract.sh

clean:
	rm -f $(BMV2_JSON) $(P4INFO)
