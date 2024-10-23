#!/usr/bin/env bash

# Ensure the script exits if any command fails
set -e

# Check if the correct number of arguments are provided
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 /path/to/repo /path/to/output"
  exit 1
fi

REPOSITORY_PATH="$1"
OUTPUT_PATH="$2"

# Create a temporary directory
TEMP_DIR=$(mktemp -d)

# Function to clean up the temporary directory
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Create mkdocs.yml in the temporary directory
cat <<EOL > "$TEMP_DIR/mkdocs.yml"
site_name: Obsidian-muistiinpanot

theme:
  name: material

markdown_extensions:
  - def_list
  - pymdownx.tasklist:
      custom_checkbox: true

use_directory_urls: true
EOL

# Clone the repository into the temporary directory
git clone "$REPOSITORY_PATH" "$TEMP_DIR/repo"

# Rsync files from the cloned repo to the docs directory
rsync -av --prune-empty-dirs --include='*/' --include='*.md' --include='*.png' --include='*.jpg' --include='*.pdf' --exclude='*' "$TEMP_DIR/repo/" "$TEMP_DIR/docs"

# Add index.md to the docs directory
cat <<EOL > "$TEMP_DIR/docs/index.md"
# Obsidian-muistiinpanot!

Tervetuloa!
EOL

# Replace Obsidian references with standard Markdown references
find "$TEMP_DIR/docs" -type f -name "*.md" | while read -r file; do
  # Handle image files
  sed -i -E 's/!\[\[([^]]+\.(png|jpg|jpeg|gif|bmp|svg))\]\]/![](\.\/Files\/\1)/g' "$file"

  # Handle non-image files (e.g., PDFs, DOCs, etc.) to create download links
  sed -i -E 's/!\[\[([^]]+)\]\]/[\1](\.\/Files\/\1)/g' "$file"
done

# Create a Python virtual environment in the temporary directory
python3 -m venv "$TEMP_DIR/venv"
source "$TEMP_DIR/venv/bin/activate"

# Install MkDocs and the Material theme in the virtual environment
pip install mkdocs mkdocs-material

# Build the site
mkdocs build --config-file "$TEMP_DIR/mkdocs.yml" --site-dir "$TEMP_DIR/site"

# Deactivate and remove the virtual environment
deactivate

# Sync the built site to the output path
rsync -av "$TEMP_DIR/site/" "$OUTPUT_PATH"

# Temporary directory and its contents will be cleaned up automatically
echo "Obsidian notes built and copied successfully."
