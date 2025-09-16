format:
	dart format --line-length 80 --set-exit-if-changed ./lib

run:
	serverpod generate
	dart bin/main.dart --apply-migrations

migration:
	serverpod generate
	serverpod create-migration
	dart bin/main.dart --apply-migrations --role=maintenance

generate:
	serverpod generate

# Generate Open Graph image from the vector logo automatically.
# Produces web/static/images/og-fiskebors-override.png that the server serves directly.
# Requirements: rsvg-convert (librsvg). Inkscape path can be added later if needed.
og-image:
	@echo "Generating OG image (1200x630) from SVG..."
	@mkdir -p web/static/images web/static/tmp
	# 1) Rasterize SVG to a large transparent PNG (keeping aspect ratio)
	rsvg-convert -w 2000 "web/static/images/Color logo - no background.svg" -o web/static/tmp/logo.png
	# 2) Compose onto 1200x630 canvas with brand background and padding using Dart image
	dart tool/compose_og_image.dart \
	  --input web/static/tmp/logo.png \
	  --output web/static/images/og-fiskebors-override.png \
	  --bg "255,244,238" \
	  --padding 72
	@rm -f web/static/tmp/logo.png
	@echo "Wrote web/static/images/og-fiskebors-override.png"
