#!/bin/sh
# Copyright (c) 2017-2021 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

# Install libdb5.3 (Berkeley DB).

export LC_ALL=C
set -e

if [ -z "${1}" ]; then
  echo "Usage: $0 <base-dir> [<extra-bdb-configure-flag> ...]"
  echo
  echo "Must specify a single argument: the directory in which db5 will be built."
  echo "This is probably \`pwd\` if you're at the root of the groestlcoin repository."
  exit 1
fi

expand_path() {
  cd "${1}" && pwd -P
}

BDB_PREFIX="$(expand_path "${1}")/db5"; shift;
BDB_VERSION='db-5.3.28.NC'
BDB_HASH='76a25560d9e52a198d37a31440fd07632b5f1f8f9f2b6d5438f4bc3e7c9013ef'
BDB_URL="https://download.oracle.com/berkeley-db/${BDB_VERSION}.tar.gz"

check_exists() {
  command -v "$1" >/dev/null
}

sha256_check() {
  # Args: <sha256_hash> <filename>
  #
  if [ "$(uname)" = "FreeBSD" ]; then
    # sha256sum exists on FreeBSD, but takes different arguments than the GNU version
    sha256 -c "${1}" "${2}"
  elif check_exists sha256sum; then
    echo "${1} ${2}" | sha256sum -c
  elif check_exists sha256; then
    echo "${1} ${2}" | sha256 -c
  else
    echo "${1} ${2}" | shasum -a 256 -c
  fi
}

http_get() {
  # Args: <url> <filename> <sha256_hash>
  #
  # It's acceptable that we don't require SSL here because we manually verify
  # content hashes below.
  #
  if [ -f "${2}" ]; then
    echo "File ${2} already exists; not downloading again"
  elif check_exists curl; then
    curl --insecure --retry 5 "${1}" -o "${2}"
  elif check_exists wget; then
    wget --no-check-certificate "${1}" -O "${2}"
  else
    echo "Simple transfer utilities 'curl' and 'wget' not found. Please install one of them and try again."
    exit 1
  fi

  sha256_check "${3}" "${2}"
}

# Ensure the commands we use exist on the system
if ! check_exists patch; then
    echo "Command-line tool 'patch' not found. Install patch and try again."
    exit 1
fi

mkdir -p "${BDB_PREFIX}"
http_get "${BDB_URL}" "${BDB_VERSION}.tar.gz" "${BDB_HASH}"
tar -xzvf ${BDB_VERSION}.tar.gz -C "$BDB_PREFIX"
cd "${BDB_PREFIX}/${BDB_VERSION}/"

# Apply a patch necessary when building with clang and c++11 (see https://community.oracle.com/thread/3952592)
patch --ignore-whitespace -p1 << 'EOF'
--- original/src/dbinc/atomic.h	2013-09-09 17:35:08.000000000 +0200
+++ patched/src/dbinc/atomic.h	2020-12-15 17:47:20.535316800 +0100
@@ -70,7 +70,7 @@
  * These have no memory barriers; the caller must include them when necessary.
  */
 #define	atomic_read(p)		((p)->value)
-#define	atomic_init(p, val)	((p)->value = (val))
+#define	atomic_init_db(p, val)	((p)->value = (val))

 #ifdef HAVE_ATOMIC_SUPPORT

@@ -144,7 +144,7 @@
 #define	atomic_inc(env, p)	__atomic_inc(p)
 #define	atomic_dec(env, p)	__atomic_dec(p)
 #define	atomic_compare_exchange(env, p, o, n)	\
-	__atomic_compare_exchange((p), (o), (n))
+	__atomic_compare_exchange_db((p), (o), (n))
 static inline int __atomic_inc(db_atomic_t *p)
 {
 	int	temp;
@@ -176,7 +176,7 @@
  * http://gcc.gnu.org/onlinedocs/gcc-4.1.0/gcc/Atomic-Builtins.html
  * which configure could be changed to use.
  */
-static inline int __atomic_compare_exchange(
+static inline int __atomic_compare_exchange_db(
 	db_atomic_t *p, atomic_value_t oldval, atomic_value_t newval)
 {
 	atomic_value_t was;
@@ -206,7 +206,7 @@
 #define	atomic_dec(env, p)	(--(p)->value)
 #define	atomic_compare_exchange(env, p, oldval, newval)		\
 	(DB_ASSERT(env, atomic_read(p) == (oldval)),		\
-	atomic_init(p, (newval)), 1)
+	atomic_init_db(p, (newval)), 1)
 #else
 #define atomic_inc(env, p)	__atomic_inc(env, p)
 #define atomic_dec(env, p)	__atomic_dec(env, p)
diff -Naur original/src/dbinc/win_db.h patched/src/dbinc/win_db.h
--- original/src/dbinc/win_db.h	2013-09-09 17:35:08.000000000 +0200
+++ patched/src/dbinc/win_db.h	2020-12-15 17:47:29.330049300 +0100
@@ -46,7 +46,7 @@
 #include <windows.h>
 #include <winsock2.h>
 #ifndef DB_WINCE
-#include <WinIoCtl.h>
+#include <winioctl.h>
 #endif

 #ifdef HAVE_GETADDRINFO
diff -Naur original/src/mp/mp_fget.c patched/src/mp/mp_fget.c
--- original/src/mp/mp_fget.c	2013-09-09 17:35:09.000000000 +0200
+++ patched/src/mp/mp_fget.c	2020-12-15 17:47:20.618078700 +0100
@@ -649,7 +649,7 @@

 		/* Initialize enough so we can call __memp_bhfree. */
 		alloc_bhp->flags = 0;
-		atomic_init(&alloc_bhp->ref, 1);
+		atomic_init_db(&alloc_bhp->ref, 1);
 #ifdef DIAGNOSTIC
 		if ((uintptr_t)alloc_bhp->buf & (sizeof(size_t) - 1)) {
 			__db_errx(env, DB_STR("3025",
@@ -955,7 +955,7 @@
 			MVCC_MPROTECT(bhp->buf, mfp->pagesize,
 			    PROT_READ);

-		atomic_init(&alloc_bhp->ref, 1);
+		atomic_init_db(&alloc_bhp->ref, 1);
 		MUTEX_LOCK(env, alloc_bhp->mtx_buf);
 		alloc_bhp->priority = bhp->priority;
 		alloc_bhp->pgno = bhp->pgno;
diff -Naur original/src/mp/mp_mvcc.c patched/src/mp/mp_mvcc.c
--- original/src/mp/mp_mvcc.c	2013-09-09 17:35:09.000000000 +0200
+++ patched/src/mp/mp_mvcc.c	2020-12-15 17:47:20.593279600 +0100
@@ -276,7 +276,7 @@
 #else
 	memcpy(frozen_bhp, bhp, SSZA(BH, buf));
 #endif
-	atomic_init(&frozen_bhp->ref, 0);
+	atomic_init_db(&frozen_bhp->ref, 0);
 	if (mutex != MUTEX_INVALID)
 		frozen_bhp->mtx_buf = mutex;
 	else if ((ret = __mutex_alloc(env, MTX_MPOOL_BH,
@@ -428,7 +428,7 @@
 #endif
 		alloc_bhp->mtx_buf = mutex;
 		MUTEX_LOCK(env, alloc_bhp->mtx_buf);
-		atomic_init(&alloc_bhp->ref, 1);
+		atomic_init_db(&alloc_bhp->ref, 1);
 		F_CLR(alloc_bhp, BH_FROZEN);
 	}

diff -Naur original/src/mp/mp_region.c patched/src/mp/mp_region.c
--- original/src/mp/mp_region.c	2013-09-09 17:35:09.000000000 +0200
+++ patched/src/mp/mp_region.c	2020-12-15 17:47:20.566905300 +0100
@@ -245,7 +245,7 @@
 			     MTX_MPOOL_FILE_BUCKET, 0, &htab[i].mtx_hash)) != 0)
 				return (ret);
 			SH_TAILQ_INIT(&htab[i].hash_bucket);
-			atomic_init(&htab[i].hash_page_dirty, 0);
+			atomic_init_db(&htab[i].hash_page_dirty, 0);
 		}

 		/*
@@ -302,7 +302,7 @@
 		} else
 			hp->mtx_hash = mtx_base + (i % dbenv->mp_mtxcount);
 		SH_TAILQ_INIT(&hp->hash_bucket);
-		atomic_init(&hp->hash_page_dirty, 0);
+		atomic_init_db(&hp->hash_page_dirty, 0);
 #ifdef HAVE_STATISTICS
 		hp->hash_io_wait = 0;
 		hp->hash_frozen = hp->hash_thawed = hp->hash_frozen_freed = 0;
diff -Naur original/src/mutex/mut_method.c patched/src/mutex/mut_method.c
--- original/src/mutex/mut_method.c	2013-09-09 17:35:09.000000000 +0200
+++ patched/src/mutex/mut_method.c	2020-12-15 17:47:20.642426300 +0100
@@ -474,7 +474,7 @@
 	MUTEX_LOCK(env, mtx);
 	ret = atomic_read(v) == oldval;
 	if (ret)
-		atomic_init(v, newval);
+		atomic_init_db(v, newval);
 	MUTEX_UNLOCK(env, mtx);

 	return (ret);
diff -Naur original/src/mutex/mut_tas.c patched/src/mutex/mut_tas.c
--- original/src/mutex/mut_tas.c	2013-09-09 17:35:09.000000000 +0200
+++ patched/src/mutex/mut_tas.c	2020-12-15 17:47:20.662067500 +0100
@@ -47,7 +47,7 @@

 #ifdef HAVE_SHARED_LATCHES
 	if (F_ISSET(mutexp, DB_MUTEX_SHARED))
-		atomic_init(&mutexp->sharecount, 0);
+		atomic_init_db(&mutexp->sharecount, 0);
 	else
 #endif
 	if (MUTEX_INIT(&mutexp->tas)) {
@@ -536,7 +536,7 @@
 			F_CLR(mutexp, DB_MUTEX_LOCKED);
 			/* Flush flag update before zeroing count */
 			MEMBAR_EXIT();
-			atomic_init(&mutexp->sharecount, 0);
+			atomic_init_db(&mutexp->sharecount, 0);
 		} else {
 			DB_ASSERT(env, sharecount > 0);
 			MEMBAR_EXIT();
EOF

# The packaged config.guess and config.sub are ancient (2009) and can cause build issues.
# Replace them with modern versions.
# See https://github.com/bitcoin/bitcoin/issues/16064
CONFIG_GUESS_URL='https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=4550d2f15b3a7ce2451c1f29500b9339430c877f'
CONFIG_GUESS_HASH='c8f530e01840719871748a8071113435bdfdf75b74c57e78e47898edea8754ae'
CONFIG_SUB_URL='https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=4550d2f15b3a7ce2451c1f29500b9339430c877f'
CONFIG_SUB_HASH='3969f7d5f6967ccc6f792401b8ef3916a1d1b1d0f0de5a4e354c95addb8b800e'

rm -f "dist/config.guess"
rm -f "dist/config.sub"

http_get "${CONFIG_GUESS_URL}" dist/config.guess "${CONFIG_GUESS_HASH}"
http_get "${CONFIG_SUB_URL}" dist/config.sub "${CONFIG_SUB_HASH}"

cd build_unix/

"${BDB_PREFIX}/${BDB_VERSION}/dist/configure" \
  --enable-cxx --disable-shared --disable-replication --with-pic --prefix="${BDB_PREFIX}" \
  "${@}"

make install

echo
echo "db5 build complete."
echo
# shellcheck disable=SC2016
echo 'When compiling groestlcoind, run `./configure` in the following way:'
echo
echo "  export BDB_PREFIX='${BDB_PREFIX}'"
# shellcheck disable=SC2016
echo '  ./configure BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-5.3" BDB_CFLAGS="-I${BDB_PREFIX}/include" ...'
