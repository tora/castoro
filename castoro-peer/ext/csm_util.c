
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <stdio.h>
#include <dirent.h>

#include "ruby.h"

static void
csm_chmod_and_chown(VALUE dir, mode_t m, uid_t u, gid_t g)
{
  const char* d = RSTRING_PTR(dir);

  if (chmod(d, m) == -1) {
    rmdir(d);
    rb_sys_fail(d);
  }
  if (chown(d, u, g) == -1) {
    rmdir(d);
    rb_sys_fail(d);
  }
}

static int
csm_chmod_and_chown_dir(VALUE dir, mode_t m, uid_t u, gid_t g)
{
  const char* d = RSTRING_PTR(dir);
  DIR *pdir;
  struct dirent *ent;

  pdir = opendir(d);
  if (d == NULL) return -1;

  ent = readdir(pdir);
  while (ent) {
    if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
      const char* file = RSTRING_PTR(rb_str_cat2(rb_str_cat2(rb_str_dup(dir), "/"), ent->d_name));

      if (chown(file, u, g) == -1)     goto ensure;
      if (chmod(file, m & 0666) == -1) goto ensure;
    }
    ent = readdir(pdir);
  }

ensure:
  closedir(pdir);

  return 0;
}

static void
csm_optimistic_mkdir(VALUE base, VALUE dir, mode_t m, uid_t u, gid_t g)
{
  int existed = 0;
  VALUE parent;

  char* d = RSTRING_PTR(dir);
  if (mkdir(d, 0777) == -1) {
    switch(errno) {
      case ENOENT:
        parent = rb_funcall(rb_cFile, rb_intern("dirname"), 1, dir);
        if (RTEST(rb_funcall(rb_cFile, rb_intern("exist?"), 1, parent))) {
          rb_sys_fail(d);
        }
        csm_optimistic_mkdir(base, parent, m, u, g);
        if (mkdir(d, 0777) == -1) {
          rb_sys_fail(d);
        }
        break;

      case EEXIST:
        if (!RTEST(rb_funcall(rb_cFile, rb_intern("directory?"), 1, dir))) {
          rb_sys_fail(d);
        }
        existed = 1;
        break;

      default:
        rb_sys_fail(d);
    }
  }
  if (existed == 0) csm_chmod_and_chown(dir, m, u, g);
}

static void
csm_pessimistic_mkdir(VALUE base, VALUE dir, mode_t m, uid_t u, gid_t g)
{
  VALUE parent;

  char* d = RSTRING_PTR(dir);
  if (mkdir(d, 0777) == -1) {
    switch(errno) {
      case ENOENT:
        parent = rb_funcall(rb_cFile, rb_intern("dirname"), 1, dir);
        if (RTEST(rb_funcall(rb_cFile, rb_intern("exist?"), 1, parent))) {
          rb_sys_fail(d);
        }
        csm_optimistic_mkdir(base, parent, m, u, g);
        if (mkdir(d, 0777) == -1) {
          rb_sys_fail(d);
        }
        break;

      default:
        rb_sys_fail(d);
    }
  }
  csm_chmod_and_chown(dir, m, u, g);
}

static void
csm_move(VALUE base, VALUE src, VALUE dst, mode_t m, uid_t u, gid_t g)
{
  char* s = RSTRING_PTR(src);
  char* d = RSTRING_PTR(dst);

  struct stat st;

  if (rename(s, d) == -1)                          goto done0;
  if (stat(d, &st) == -1)                          goto done1;
  if (chown(d, u, g) == -1)                        goto done2;
  if (chmod(d, m) == -1)                           goto done3;
  if (csm_chmod_and_chown_dir(dst, m, u, g) == -1) goto done4;

  return;

done4:
  csm_chmod_and_chown_dir(dst, st.st_mode, st.st_uid, st.st_gid);
done3:
  chown(d, st.st_uid, st.st_gid);
done2:
done1:
  rename(d, s);
done0:
  rb_sys_fail(s);
}

static VALUE
rb_csm_init(VALUE self, VALUE base)
{
  if (!RTEST(rb_funcall(rb_cFile, rb_intern("directory?"), 1, base))) {
    rb_raise(rb_eArgError, "base directory not found - %s", RSTRING_PTR(base));
  }

  // path normalize.
  VALUE str = rb_funcall(rb_cFile, rb_intern("expand_path"), 1, base);
  VALUE args[1];
  args[0] = rb_str_new2("\\.*\\/$");
  VALUE regexp = rb_class_new_instance(1, args, rb_cRegexp);
  if (!RTEST(rb_funcall(regexp, rb_intern("match"), 1, str))) {
    rb_funcall(str, rb_intern("<<"), 1, rb_str_new2("/"));
  }
  rb_iv_set(self, "@base", rb_str_freeze(rb_str_dup(str)));

  args[0] = rb_str_new2("^\\/.*$");
  rb_iv_set(self, "absolute", rb_class_new_instance(1, args, rb_cRegexp));

  VALUE s = rb_str_new2("^");
  rb_str_cat2(s, RSTRING_PTR(rb_funcall(rb_cRegexp, rb_intern("escape"), 1, str)));
  rb_str_cat2(s, ".*$");
  args[0] = s;
  rb_iv_set(self, "validpath", rb_class_new_instance(1, args, rb_cRegexp));

  rb_obj_freeze(self);
  return self;
}

static VALUE
rb_csm_mkdir(VALUE self, VALUE src, VALUE mode, VALUE uid, VALUE gid)
{
  FilePathValue(src);
  VALUE  s = rb_str_encode_ospath(src);
  mode_t m = NUM2UINT(mode);
  uid_t  u = NUM2UIDT(uid);
  gid_t  g = NUM2GIDT(gid);

  if (getpwuid(u) == 0) rb_raise(rb_eArgError, "can't find user for %d", (int)u);
  if (getgrgid(g) == 0) rb_raise(rb_eArgError, "can't find group for %d", (int)g);

  if (!RTEST(rb_funcall(rb_iv_get(self, "absolute"), rb_intern("=~"), 1, s))) {
    rb_raise(rb_eArgError, "relative path cannot set to be source.");
  }
  if (!RTEST(rb_funcall(rb_iv_get(self, "validpath"), rb_intern("=~"), 1, s))) {
    rb_raise(rb_eArgError, "Invalid source directory - %s", RSTRING_PTR(s));
  }

  if (RTEST(rb_funcall(rb_cFile, rb_intern("exist?"), 1, s))) {
    rb_raise(rb_eArgError, "source path already exist.");
  }

  csm_pessimistic_mkdir(rb_iv_get(self, "@base"), s, m, u, g);

  return self;
}

static VALUE
rb_csm_move(VALUE self, VALUE src, VALUE dst, VALUE mode, VALUE uid, VALUE gid)
{
  FilePathValue(src);
  FilePathValue(dst);
  VALUE  s = rb_str_encode_ospath(src);
  VALUE  d = rb_str_encode_ospath(dst);
  mode_t m = NUM2UINT(mode);
  uid_t  u = NUM2UIDT(uid);
  gid_t  g = NUM2GIDT(gid);

  if (getpwuid(u) == 0) rb_raise(rb_eArgError, "can't find user for %d", (int)u);
  if (getgrgid(g) == 0) rb_raise(rb_eArgError, "can't find group for %d", (int)g);

  if (!RTEST(rb_funcall(rb_iv_get(self, "absolute"), rb_intern("=~"), 1, s))) {
    rb_raise(rb_eArgError, "relative path cannot set to be source.");
  }
  if (!RTEST(rb_funcall(rb_iv_get(self, "absolute"), rb_intern("=~"), 1, d))) {
    rb_raise(rb_eArgError, "relative path cannot set to be dest.");
  }
  if (!RTEST(rb_funcall(rb_iv_get(self, "validpath"), rb_intern("=~"), 1, s))) {
    rb_raise(rb_eArgError, "Invalid source directory - %s", RSTRING_PTR(s));
  }
  if (!RTEST(rb_funcall(rb_iv_get(self, "validpath"), rb_intern("=~"), 1, d))) {
    rb_raise(rb_eArgError, "Invalid dest directory - %s", RSTRING_PTR(d));
  }

  if (!RTEST(rb_funcall(rb_cFile, rb_intern("exist?"), 1, s))) {
    rb_raise(rb_eArgError, "source path not exist.");
  }
  if (RTEST(rb_funcall(rb_cFile, rb_intern("exist?"), 1, d))) {
    rb_raise(rb_eArgError, "dest path already exist.");
  }

  VALUE p = rb_funcall(rb_cFile, rb_intern("dirname"), 1, d);
  csm_optimistic_mkdir(rb_iv_get(self, "@base"), p, m, u, g);

  csm_move(rb_iv_get(self, "@base"), s, d, m, u, g);

  return self;
}

static VALUE
rb_csm_base_get(VALUE self)
{
  return rb_iv_get(self, "@base");
}

void
Init_csm_util()
{
  VALUE cCastoro     = rb_define_module("Castoro");
  VALUE cPeer        = rb_define_module_under(cCastoro, "Peer");
  VALUE cManipulator = rb_define_module_under(cPeer, "Manipulator");
  VALUE cCsm         = rb_define_class_under(cManipulator, "CsmUtil", rb_cObject);

  rb_define_method(cCsm, "initialize", RUBY_METHOD_FUNC(rb_csm_init), 1);
  rb_define_method(cCsm, "mkdir", RUBY_METHOD_FUNC(rb_csm_mkdir), 4);
  rb_define_method(cCsm, "move", RUBY_METHOD_FUNC(rb_csm_move), 5);
  rb_define_method(cCsm, "base", RUBY_METHOD_FUNC(rb_csm_base_get), 0);
}

