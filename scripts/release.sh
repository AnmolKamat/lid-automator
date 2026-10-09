#!/usr/bin/env bash
set -e

TAG="$1"

if [ -z "$TAG" ]; then
    echo "Usage: ./scripts/release.sh <tag> (e.g. ./scripts/release.sh v0.1.2)"
    exit 1
fi

# Ensure tag starts with v
if [[ ! "$TAG" =~ ^v ]]; then
    TAG="v${TAG}"
fi

echo "🚀 Preparing release for ${TAG}..."

# Ensure working tree clean
if ! git diff-index --quiet HEAD --; then
    echo "❌ Working tree has uncommitted changes. Commit or stash them first."
    exit 1
fi

# Push main first
echo "Pushing main branch..."
git push origin main

# Tag and push
echo "Tagging ${TAG}..."
git tag -f "${TAG}"
git push origin -f "${TAG}"

# Calculate SHA256 of GitHub archive
echo "Waiting for GitHub release archive to compute SHA256..."
ARCHIVE_URL="https://github.com/AnmolKamat/lid-automator/archive/refs/tags/${TAG}.tar.gz"

for i in {1..6}; do
    HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "$ARCHIVE_URL")
    if [ "$HTTP_CODE" = "200" ]; then
        break
    fi
    echo "Waiting for archive... ($i/6)"
    sleep 3
done

SHA256=$(curl -sL "$ARCHIVE_URL" | shasum -a 256 | awk '{print $1}')
echo "Calculated SHA256: ${SHA256}"

# Update local Formula in lid-automator
sed -i '' -E "s|url \"https://github.com/AnmolKamat/lid-automator/archive/refs/tags/.*\.tar\.gz\"|url \"${ARCHIVE_URL}\"|" Formula/lid-automator.rb
sed -i '' -E "s|sha256 \".*\"|sha256 \"${SHA256}\"|" Formula/lid-automator.rb

if ! git diff-index --quiet HEAD -- Formula/lid-automator.rb; then
    git commit -m "chore: bump Formula to ${TAG}" Formula/lid-automator.rb
    git push origin main
fi

# Update Homebrew Tap repo if present locally
TAP_DIR="/opt/homebrew/Library/Taps/anmolkamat/homebrew-tap"
if [ -d "$TAP_DIR" ]; then
    echo "Updating local Homebrew tap in ${TAP_DIR}..."
    cp Formula/lid-automator.rb "${TAP_DIR}/Formula/lid-automator.rb"
    git -C "$TAP_DIR" commit -am "bump lid-automator to ${TAG}" || true
    git -C "$TAP_DIR" push origin main
    echo "✅ Homebrew tap updated and pushed!"
fi

echo ""
echo "🎉 Release ${TAG} complete!"
echo "   GitHub Release: https://github.com/AnmolKamat/lid-automator/releases/tag/${TAG}"
echo "   Homebrew Formula: Updated with SHA256 ${SHA256}"
echo ""
