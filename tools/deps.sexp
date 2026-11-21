;;; Pinned third-party dependencies, fetched into .deps/ by tools/deps.lisp.
;;; Each entry: (directory-name git-url commit)
;;; Pinned by commit so builds are reproducible without Quicklisp.
;;; Only GitHub-hosted repositories: other hosts are unreachable from the
;;; cloud agent environment.
(("parachute"               "https://github.com/Shinmera/parachute"           "9a6679e611925dfb59067393c5b7996f69501aa6")
 ("documentation-utils"     "https://github.com/Shinmera/documentation-utils" "fcbd927dee7f311915a27ee557e3db1d4510403c")
 ("form-fiddle"             "https://github.com/Shinmera/form-fiddle"         "706c4fa07552d56b372f728a225021a14db3f62e")
 ("trivial-indent"          "https://github.com/Shinmera/trivial-indent"      "87b35ff9202b107230e35790e93c471cc7880900")
 ("trivial-custom-debugger" "https://github.com/phoe/trivial-custom-debugger" "802473c75d9db625b8f37b05c95dde47b67c52fa"))
