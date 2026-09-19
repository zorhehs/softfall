cask "softfall" do
  version "0.2.0"
  sha256 "c7d76a3273f88bbaea8d8f4cccbdab24fee052d38ebfd1795b40b9395a9e5776"

  url "https://github.com/zorhehs/softfall/releases/download/v#{version}/Softfall-#{version}.zip"
  name "Softfall"
  desc "Ambient weather overlay for macOS with fully synthesized sound"
  homepage "https://github.com/zorhehs/softfall"

  # The bare symbol means "this version or newer". Homebrew 7 deprecated the
  # string-comparison form and named this exact replacement in its own warning.
  depends_on macos: :sonoma

  app "Softfall.app"

  # Homebrew 7 deprecated this block in favour of a declared `postflight_steps`,
  # and will stop loading it on 2027-12-11. It is not converted yet on purpose:
  # the declared form takes literal arguments with `{{token}}` paths rather than
  # Ruby interpolation, so `#{appdir}` here does not carry across unchanged, and
  # there is no `brew` on the machine this is written on to test the conversion.
  # `brew style --fix zorhehs/softfall` converts it; that output should be
  # pasted in here and verified with `brew reinstall --cask softfall`.
  #
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
