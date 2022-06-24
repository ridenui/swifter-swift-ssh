## [1.2.6](https://github.com/ridenui/swifter-swift-ssh/compare/1.2.5...1.2.6) (2022-06-24)


### Bug Fixes

* race condition which results in the cancelation of std buffer read if stderr finishes first ([1c30001](https://github.com/ridenui/swifter-swift-ssh/commit/1c3000130e9d0afcf7ed82eb0cd7528e541638fb))

## [1.2.5](https://github.com/ridenui/swifter-swift-ssh/compare/1.2.4...1.2.5) (2022-03-04)


### Bug Fixes

* use signa_recovery to prevent further crashes ([007d2a1](https://github.com/ridenui/swifter-swift-ssh/commit/007d2a1dee1f1800c565d424c6fbbb18176fe5e2))

## [1.2.4](https://github.com/ridenui/swifter-swift-ssh/compare/1.2.3...1.2.4) (2022-02-27)


### Bug Fixes

* some more exc_bad_access ([848eb83](https://github.com/ridenui/swifter-swift-ssh/commit/848eb830e57c5bf4f557a62cf64395f00a0e48c4))

## [1.2.3](https://github.com/ridenui/swifter-swift-ssh/compare/1.2.2...1.2.3) (2022-02-27)


### Bug Fixes

* auto close connection ([f645fb8](https://github.com/ridenui/swifter-swift-ssh/commit/f645fb8e260cf8d95065e314fa9cc5614e061095))

## [1.2.2](https://github.com/ridenui/swifter-swift-ssh/compare/1.2.1...1.2.2) (2022-02-25)


### Bug Fixes

* hopefully exc_bad_access ([76264aa](https://github.com/ridenui/swifter-swift-ssh/commit/76264aa989bda09659203d58b361b96f75f7323e))

## [1.2.1](https://github.com/ridenui/swifter-swift-ssh/compare/1.2.0...1.2.1) (2022-02-23)

# [1.2.0](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.18...1.2.0) (2022-02-23)


### Bug Fixes

* more errors ([46611ea](https://github.com/ridenui/swifter-swift-ssh/commit/46611ea13678bfc2a9cfff37a9d710eadc3f5701))


### Features

* add debug build of libssh to ios ([3152149](https://github.com/ridenui/swifter-swift-ssh/commit/315214968f4c12e24cf50c6702aab0fba79e0777))

## [1.1.18](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.17...1.1.18) (2022-02-23)

## [1.1.17](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.16...1.1.17) (2022-02-21)


### Bug Fixes

* out of range error ([8df24f9](https://github.com/ridenui/swifter-swift-ssh/commit/8df24f9b6f8a3cf9436a47e66fbf1943e6b66129))

## [1.1.16](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.15...1.1.16) (2022-02-20)


### Bug Fixes

* do not reuse a broken connection ([9314d4f](https://github.com/ridenui/swifter-swift-ssh/commit/9314d4fc9a4a3d7ce36b2bc7c9fc4cc4c246903e))

## [1.1.15](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.14...1.1.15) (2022-02-20)


### Bug Fixes

* rewrite libssh backend connection to fix all EXC_BAD_ACCESS errors ([7001fa4](https://github.com/ridenui/swifter-swift-ssh/commit/7001fa432f09857faed205317a6f4b6fc5bd6573))

## [1.1.14](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.13...1.1.14) (2022-02-19)


### Bug Fixes

* make all libssh calls safe ([b6aad1b](https://github.com/ridenui/swifter-swift-ssh/commit/b6aad1bc0cc64dcacf9a2e5f4807f6188f56af5e))

## [1.1.13](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.12...1.1.13) (2022-02-18)


### Bug Fixes

* add a lock to every libssh call ([99eddce](https://github.com/ridenui/swifter-swift-ssh/commit/99eddce6e9117fc30478027b80f25a44414c55f8))

## [1.1.12](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.11...1.1.12) (2022-02-18)


### Bug Fixes

* more EXC_BAD_ACCESS ([700798d](https://github.com/ridenui/swifter-swift-ssh/commit/700798deabfa330c797907a00e1776075edd947f))

## [1.1.11](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.10...1.1.11) (2022-02-18)


### Bug Fixes

* more EXC_BAD_ACCCESS ([cab6264](https://github.com/ridenui/swifter-swift-ssh/commit/cab6264fd558e48da482a3abe1da83e7267a8173))

## [1.1.10](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.9...1.1.10) (2022-02-17)


### Bug Fixes

* prevent some more exec_bad_access ([b82d68f](https://github.com/ridenui/swifter-swift-ssh/commit/b82d68f22af4c93ab0bad8d9c6f0d6796254a000))

## [1.1.9](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.8...1.1.9) (2022-02-03)


### Bug Fixes

* prevent another channel bad access crash ([32a7b6b](https://github.com/ridenui/swifter-swift-ssh/commit/32a7b6bec5c44fa37987c4bd9b0e4e3173464d49))

## [1.1.8](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.7...1.1.8) (2022-02-03)


### Bug Fixes

* improve reliability of stdout and stderr captcha ([a9fb961](https://github.com/ridenui/swifter-swift-ssh/commit/a9fb9614894a7be7124ea8d8ebec8a34a5544f19))

## [1.1.7](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.6...1.1.7) (2022-01-23)

## [1.1.6](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.5...1.1.6) (2022-01-15)

## [1.1.5](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.4...1.1.5) (2022-01-15)


### Bug Fixes

* **connect:** run ssh_connect with doUnsafeTask ([d97443e](https://github.com/ridenui/swifter-swift-ssh/commit/d97443e9190676a910511c86ce7544b182911238))

## [1.1.4](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.3...1.1.4) (2022-01-14)


### Bug Fixes

* **ssh:** try to prevent socket not unconnected error ([2a2b760](https://github.com/ridenui/swifter-swift-ssh/commit/2a2b760352ff85dbcdd0557fe2041538e876dd4f))

## [1.1.3](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.2...1.1.3) (2022-01-14)


### Bug Fixes

* **ssh:** prevent bad access when calling disconnect on an active connection ([057612b](https://github.com/ridenui/swifter-swift-ssh/commit/057612bd3c3818f001b76743e5d67b18527530d7))

## [1.1.2](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2022-01-14)


### Bug Fixes

* **ci:** add missing release-it plugin ([549654e](https://github.com/ridenui/swifter-swift-ssh/commit/549654e6ddec7bd13c623bff0dba63123fbedb0e))
* **ci:** add release script ([1703af4](https://github.com/ridenui/swifter-swift-ssh/commit/1703af439181a79c27d1e3c32af64a4d9dfe3830))
* **ci:** disable npm part of release-it ([c206b96](https://github.com/ridenui/swifter-swift-ssh/commit/c206b966abf8f4306548cea03c318248b40a815d))
* **ci:** fix release it regex ([f0a9e1b](https://github.com/ridenui/swifter-swift-ssh/commit/f0a9e1b384932555c7c86e3262cbfc11857308ca))
* **ci:** use regex capture group for version ([797c724](https://github.com/ridenui/swifter-swift-ssh/commit/797c724f9ce38f70b87a2ef1086a6c85f06a953c))



## [1.1.1](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2022-01-14)


### Bug Fixes

* **ci:** add podPushArgs arguments ([461b88b](https://github.com/ridenui/swifter-swift-ssh/commit/461b88ba389c37ae6f45fc01ff46d7dd2bcafb56))



# [1.1.0](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2022-01-14)


### Bug Fixes

* **ci:** add missing conventional-changelog-conventionalcommits to extra_plugins ([2658269](https://github.com/ridenui/swifter-swift-ssh/commit/2658269b41fc71ff8bde48a9ac8beeda6126efd8))
* **ci:** add name via package.json and fix release branche ([acdd8bb](https://github.com/ridenui/swifter-swift-ssh/commit/acdd8bb1646fc9ceba3ffb3e269bb8705f823762))
* **ci:** rearrange [@semantic-release](https://github.com/semantic-release) plugins ([76e9dd5](https://github.com/ridenui/swifter-swift-ssh/commit/76e9dd5d616e4216158093554244b88aa423ea62))
* **ci:** setup correct node version ([cd39528](https://github.com/ridenui/swifter-swift-ssh/commit/cd3952833bfa531ffc4ee77a449048ba0f39701d))
* **ci:** try to fix github push in ci publish action ([59a7607](https://github.com/ridenui/swifter-swift-ssh/commit/59a76071e558732627aa948c4cc0bda6156ad56d))
* **ci:** try to fix npm install for semantic-release extra plugins ([13596b9](https://github.com/ridenui/swifter-swift-ssh/commit/13596b99a69c8109378b1c76558c1af3611b8e46))
* **ci:** use custom @ridenui/semantic-release-cocoapods ([6b8f1e6](https://github.com/ridenui/swifter-swift-ssh/commit/6b8f1e636e4809bdd0316a365614dc69320a410f))
* **release:** correct pod lint args ([a96de5f](https://github.com/ridenui/swifter-swift-ssh/commit/a96de5f054bfe796484e224a88dd994c6047cd4d))


### Features

* **ci:** use [@semantic-release](https://github.com/semantic-release) for cocoapods release ([dceeedb](https://github.com/ridenui/swifter-swift-ssh/commit/dceeedbdce1eb3d61cf54a2593f3d1570b99a8a5))



## [1.0.10](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2022-01-14)


### Bug Fixes

* "ssh_socket_connect called on socket not unconnected" after device sleep ([4fb5466](https://github.com/ridenui/swifter-swift-ssh/commit/4fb5466ad3585757b124803f0666951fbcb38c95))



## [1.0.9](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2022-01-13)


### Bug Fixes

* try to prevent dead lock on main thread when disconnecting a dead connection ([76188ce](https://github.com/ridenui/swifter-swift-ssh/commit/76188cec9bc822b857afaacbf52c33799609150d))



## [1.0.8](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-23)


### Features

* auto find and close stuck connection in the connection pool ([8cad98c](https://github.com/ridenui/swifter-swift-ssh/commit/8cad98c8bd1cf22d1b43299ac02a24172b96269a))



## [1.0.7](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-23)


### Bug Fixes

* prevent crash if there is an invalid connection ([24fcfc5](https://github.com/ridenui/swifter-swift-ssh/commit/24fcfc528520dbe718ef4bad2bbc6e65cf883414))



## [1.0.6](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-23)


### Bug Fixes

* increase Task sleep if no connection is available ([9d72b0d](https://github.com/ridenui/swifter-swift-ssh/commit/9d72b0ddeb17903dedcbcd395bed566e6a6752e0))



## [1.0.5](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-23)


### Bug Fixes

* improve pool connection handling ([fe89a03](https://github.com/ridenui/swifter-swift-ssh/commit/fe89a03b6fbc82477f37716f7e6c8dc2251fcaf2))



## [1.0.4](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-23)



## [1.0.3](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-23)


### Bug Fixes

* prevent deadlocks on ios ([91f886b](https://github.com/ridenui/swifter-swift-ssh/commit/91f886b79b8247e9316586e9520a1d150bff549d))



## [1.0.1](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-22)



# [1.0.0](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-21)


### Features

* connection pool ([846c7a1](https://github.com/ridenui/swifter-swift-ssh/commit/846c7a127f682558c0fc5cc35f5bc5560064fdd9))



## [0.0.1](https://github.com/ridenui/swifter-swift-ssh/compare/1.1.1...1.1.2) (2021-12-20)


### Bug Fixes

* make valid podspec ([8ca35b2](https://github.com/ridenui/swifter-swift-ssh/commit/8ca35b2d661995f0aaa78d9d081d58afcfdc3ea5))
* prevent deadlock ([5922d82](https://github.com/ridenui/swifter-swift-ssh/commit/5922d82fab2231c4f8686edbc1fcbc0287934022))
* race condition ([14c6991](https://github.com/ridenui/swifter-swift-ssh/commit/14c6991b8584097a7fe4e2787346d98b73e781b8))


### Features

* add first working exec method ([430a75a](https://github.com/ridenui/swifter-swift-ssh/commit/430a75a561533f23c2afbc6f60eb7fb8f0a97632))
* use non blocking read ([9ee8e38](https://github.com/ridenui/swifter-swift-ssh/commit/9ee8e38c38127adc9ec0a3bf26067ddea8095ae7))

