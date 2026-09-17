cask "softfall" do
  version "0.0.0"
  sha256 :no_check

  url "https://github.com/zorhehs/softfall/releases/download/v#{version}/Softfall-#{version}.zip"
  name "Softfall"
  desc "Ambient weather overlay for macOS with fully synthesized sound"
  homepage "https://github.com/zorhehs/softfall"

  depends_on macos: ">= :sonoma"

  app "Softfall.app"

  # The release build is ad-hoc signed rather than notarised, so macOS would
  # otherwise refuse to open it. Clearing the quarantine flag on a binary the
  # user has deliberately installed is the same thing they would do by hand
  # with right-click > Open. Set the CODESIGN_IDENTITY secret and add a
  # notarisation step to the release workflow to make this unnecessary.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Softfall.app"],
                   sudo: false
  end

  uninstall quit: "io.github.zorhehs.softfall"

  zap trash: [
    "~/Library/Preferences/io.github.zorhehs.softfall.plist",
  ]
end
