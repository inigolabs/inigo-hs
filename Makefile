clone-and-patch:
	rm -rf graphql-engine
	git clone https://github.com/hasura/graphql-engine.git
	git apply --directory graphql-engine hasura.patch
	echo $(shell git describe --tags --always `git rev-list --tags --max-count=1`) > graphql-engine/server/CURRENT_VERSION

build: clone-and-patch
	cd graphql-engine && \
	cabal build graphql-engine && \
	cd frontend && yarn install && yarn server-build:ce

run:
	HASURA_GRAPHQL_ENABLE_CONSOLE=true \
	HASURA_GRAPHQL_CONSOLE_ASSETS_DIR=/home/soluchok/projects/inigo-hs/graphql-engine/frontend/dist/apps/server-assets-console-ce \
	INIGO_SERVICE_TOKEN=eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE2ODgzNzQ5NzMsInVzZXJfcHJvZmlsZSI6InNpZGVjYXIiLCJ1c2VyX3JvbGVzIjpbInNpZGVjYXIiXSwidXNlcl9pZCI6MTYsInVzZXJfbmFtZSI6IkluaWdvL2hhc3VyYSIsIm9yZ19pZCI6MywidG9rZW4iOiJjMDJhNmEwYS1hNzBkLTRkNTMtYTdjMy0xNTA5NGYzMTAzNDgiLCJ0b2tlblR5cGUiOiJzZXJ2aWNlX3Rva2VuIiwiZW5jcnlwdGlvbl9rZXkiOiI2aVUxVDR3bHRkU1hldWxkd3Bwdm5mN3EvWXgxNUFRWDVTVXkvUlRPN0xjPSJ9.JMljFs-qJJyfQtFX_uR6CxtxpMohDKZ_PlHenswpt4GX0fRtQBnEIOEXhPWS0_bQ-uL_qn9aMPlYqI99-6a0uw \
	INIGO_STORAGE_URL=http://192.168.49.2:30020/query \
	INIGO_SERVICE_URL=http://192.168.49.2:30018/query \
	INIGO_EGRESS_URL=http://localhost:9090/v1/graphql \
	INIGO_LIB_PATH=/home/soluchok/projects/inigo/dist_ffi/inigo_linux_amd64/libinigo.so \
	graphql-engine/dist-newstyle/build/x86_64-linux/ghc-9.4.5/graphql-engine-1.0.0/x/graphql-engine/opt/build/graphql-engine/graphql-engine --metadata-database-url postgres://postgres:redpanda123@192.168.49.2:30003/dev_inigo serve --server-port 9090
