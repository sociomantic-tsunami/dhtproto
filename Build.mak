export ASSERT_ON_STOMPING_PREVENTION=1

override LDFLAGS += -llzo2 -lebtree -lrt -lgcrypt -lgpg-error -lglib-2.0 -lpcre
override DFLAGS  += -w -de
DC:=dmd-transitional

# Ubuntu bionic requires builds to use position independent code and
# dmd-transitional does not set the flag -fPIC by default
ifeq ($(DC),dmd-transitional)
override DFLAGS += -fPIC
endif

$B/fakedht: $C/src/fakedht/main.d
$B/fakedht: override LDFLAGS += -llzo2 -lebtree -lrt -lpcre

all += $B/fakedht

$O/test-fakedht: $B/fakedht

$B/dhtapp: $C/src/dummydhtapp/main.d

$O/test-dhtrestart: $B/dhtapp
$O/test-dhtrestart: override LDFLAGS += -llzo2 -lebtree  -lrt -lpcre

$O/test-env: $B/dhtapp
$O/test-env: override LDFLAGS += -llzo2 -lebtree  -lrt -lpcre

run-test: $O/test-fakedht
	$O/test-fakedht
