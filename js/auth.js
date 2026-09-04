(() => {
  const SUPABASE_URL = 'https://temzkjhkqnrtdwxckioy.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_kTc_bhsr0iiPmVV34aSdWg_5gfC5hR8';

  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    console.error('[Auth] Supabase client script is missing.');
    return;
  }

  const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  });

  window.angoraSupabase = supabase;

  function unlockUI() {
    document.body.style.overflow = '';
  }

  function notifyAuthState(eventName, user) {
    window.dispatchEvent(new CustomEvent('angora-auth-changed', {
      detail: {
        event: eventName || 'AUTH_DISABLED',
        user: user ? { id: user.id, email: user.email || '' } : null,
        timestamp: Date.now(),
      },
    }));
  }

  supabase.auth.onAuthStateChange((event, session) => {
    unlockUI();
    notifyAuthState(event, session?.user || null);
  });

  (async () => {
    unlockUI();

    try {
      const { data } = await supabase.auth.getSession();
      notifyAuthState('SESSION_SYNC', data?.session?.user || null);
    } catch (error) {
      console.warn('[Auth] Session check skipped:', error?.message || error);
      notifyAuthState('AUTH_DISABLED', null);
    }
  })();
})();
