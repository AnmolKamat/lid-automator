class LidAutomator < Formula
  desc "Automate scripts, notifications, and actions based on MacBook lid angles"
  homepage "https://github.com/anmolkamath/lid-automator"
  url "https://github.com/anmolkamath/lid-automator/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"
  head "https://github.com/anmolkamath/lid-automator.git", branch: "main"

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
