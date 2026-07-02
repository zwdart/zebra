.PHONY: build release clean gen-icons help

# 默认目标
help:
	@echo "Usage:"
	@echo "  make build        - Debug build"
	@echo "  make release      - Release build (optimized)"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make gen-icons    - Generate icons (requires SVG_FILE)"
	@echo ""
	@echo "Examples:"
	@echo "  make release"
	@echo "  make gen-icons SVG_FILE=../assets/icon.svg"

build:
	cargo build --bin icon-gen

release:
	cargo build --release --bin icon-gen

clean:
	cargo clean

# 生成图标 (Unix)
gen-icons: release
	@./target/release/icon-gen $(SVG_FILE)
