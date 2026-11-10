/* Keep Emacs's SIGCHLD handler on the Android APK.

   Android's Java process spawning resets SIGCHLD to its default the
   first time it runs, as when "Open with" passes a file to emacsclient.
   Emacs installs its handler only at startup, so it then stops noticing
   child processes exit.  Loaded early, this module saves Emacs's
   handler; `sigchld-restore' puts it back.  */

#include <emacs-module.h>
#include <signal.h>

int plugin_is_GPL_compatible;

static struct sigaction emacs_handler;
static int have_handler;

static emacs_value
restore (emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  struct sigaction current;

  if (!have_handler || sigaction (SIGCHLD, NULL, &current) != 0
      || current.sa_handler == emacs_handler.sa_handler)
    return env->intern (env, "nil");
  sigaction (SIGCHLD, &emacs_handler, NULL);
  return env->intern (env, "t");
}

int
emacs_module_init (struct emacs_runtime *runtime)
{
  emacs_env *env = runtime->get_environment (runtime);
  emacs_value args[2];

  if (sigaction (SIGCHLD, NULL, &emacs_handler) == 0)
    have_handler = emacs_handler.sa_handler != SIG_DFL
      && emacs_handler.sa_handler != SIG_IGN;
  args[0] = env->intern (env, "sigchld-restore");
  args[1] = env->make_function
    (env, 0, 0, restore,
     "Put back Emacs's SIGCHLD handler if something replaced it.\n"
     "Return t if it was replaced.", NULL);
  env->funcall (env, env->intern (env, "defalias"), 2, args);
  args[0] = env->intern (env, "sigchld");
  env->funcall (env, env->intern (env, "provide"), 1, args);
  return 0;
}
