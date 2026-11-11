Source: https://github.com/meettomorrow/lee-su-threads
Revision: db0476fc10cc6a738c6a6eb49ed2f1dd89174419
License: MIT (see LICENSE)

profileParser.js and dateParser.js are unmodified upstream files. Test fixtures
are copied from the same revision. The native bridge adapts the upstream session
token scanning and About This Profile request. No authentication tokens are
returned to native code, exported, or sent to a service other than Threads.
