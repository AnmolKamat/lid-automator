class LidAutomator < Formula
  desc "Automate scripts, notifications, and actions based on MacBook lid angles"
  homepage "https://github.com/AnmolKamat/lid-automator"
  url "https://github.com/AnmolKamat/lid-automator/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "9a2201188aba27f59d64a26ed28455f339d359841b4e4eea4c1e016d02c2ce9c"
  license "MIT"
  head "https://github.com/AnmolKamat/lid-automator.git", branch: "main"

  depends_on :macos
  depends_on arch: :arm64

  def install
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
    bin.install ".build/release/lid-automator"
  end

  def caveats
    <<~EOS
      To start the lid automation background daemon:
        lid-automator start

      To view active rules and lid angle:
        lid-automator status
    EOS
  end

  test do
    assert_match "MacBook Lid Automator", shell_output("#{bin}/lid-automator --help")
  end
end
