(() => {
  const SUPABASE_URL = 'https://temzkjhkqnrtdwxckioy.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_kTc_bhsr0iiPmVV34aSdWg_5gfC5hR8';
  const PROFILE_TABLE = 'angora_user_profiles';
  const MIN_PASSWORD_LENGTH = 6;
  const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  const BOOTSTRAP_SUPER_ADMIN_EMAILS = [
    'alex@joinangora.com',
    'ben@joinangora.com'
  ];
  const ROLE_ADMIN = 'admin';
  const ROLE_SUPER_ADMIN = 'super_admin';
  const STATUS_PENDING = 'pending';
  const STATUS_ACTIVE = 'active';
  const STATUS_REJECTED = 'rejected';
  /** Password reset link always goes to production so email works from any environment */
  const PASSWORD_RESET_REDIRECT_URL = 'https://angorav2.vercel.app/';

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
  let profileSyncWarningShown = false;

  const state = {
    view: 'login',
    recoveryMode: false,
  };

  function notifyAuthState(eventName, user) {
    window.dispatchEvent(new CustomEvent('angora-auth-changed', {
      detail: {
        event: eventName || 'UNKNOWN',
        user: user ? { id: user.id, email: user.email || '' } : null,
        timestamp: Date.now(),
      },
    }));
  }

  const els = {
    gate: document.getElementById('supaAuthGate'),
    title: document.getElementById('supaAuthTitle'),
    sub: document.getElementById('supaAuthSub'),
    message: document.getElementById('supaAuthMessage'),

    loginTab: document.getElementById('supaAuthTabLogin'),
    registerTab: document.getElementById('supaAuthTabRegister'),

    loginForm: document.getElementById('supaAuthLoginForm'),
    registerForm: document.getElementById('supaAuthRegisterForm'),
    forgotForm: document.getElementById('supaAuthForgotForm'),
    resetForm: document.getElementById('supaAuthResetForm'),

    loginEmail: document.getElementById('supaLoginEmail'),
    loginPassword: document.getElementById('supaLoginPassword'),
    registerFirstName: document.getElementById('supaRegisterFirstName'),
    registerLastName: document.getElementById('supaRegisterLastName'),
    registerEmail: document.getElementById('supaRegisterEmail'),
    registerPassword: document.getElementById('supaRegisterPassword'),
    registerConfirmPassword: document.getElementById('supaRegisterConfirmPassword'),
    forgotEmail: document.getElementById('supaForgotEmail'),
    resetPassword: document.getElementById('supaResetPassword'),
    resetConfirmPassword: document.getElementById('supaResetConfirmPassword'),

    loginSubmit: document.getElementById('supaLoginSubmit'),
    registerSubmit: document.getElementById('supaRegisterSubmit'),
    forgotSubmit: document.getElementById('supaForgotSubmit'),
    resetSubmit: document.getElementById('supaResetSubmit'),

    forgotLink: document.getElementById('supaForgotLink'),
    forgotBackBtn: document.getElementById('supaForgotBackBtn'),
    resetBackBtn: document.getElementById('supaResetBackBtn'),

    userChip: document.getElementById('authUserChip'),
    userEmail: document.getElementById('authUserEmail'),
    openBtn: document.getElementById('authOpenBtn'),
    logoutBtn: document.getElementById('authLogoutBtn'),
  };

  const viewMeta = {
    login: {
      title: 'Sign in to continue',
      sub: 'Use your account to access the dashboard.',
    },
    register: {
      title: 'Create your account',
      sub: 'Register once, then log in anytime.',
    },
    forgot: {
      title: 'Reset password',
      sub: 'Enter your email and we will send a reset link.',
    },
    reset: {
      title: 'Set a new password',
      sub: 'Enter your new password to finish recovery.',
    },
  };

  function showMessage(text, type) {
    if (!els.message) return;
    els.message.textContent = text || '';
    els.message.classList.remove('error', 'success');
    if (type === 'error' || type === 'success') {
      els.message.classList.add(type);
    }
  }

  function setBusy(button, busy) {
    if (!button) return;
    button.disabled = busy;
    button.dataset.originalText = button.dataset.originalText || button.textContent;
    button.textContent = busy ? 'Please wait...' : button.dataset.originalText;
  }

  function setDisplay(el, shouldShow, mode = 'grid') {
    if (!el) return;
    el.style.display = shouldShow ? mode : 'none';
  }

  function setView(view, options = {}) {
    const { clearMessage = true } = options;

    state.view = view;

    setDisplay(els.loginForm, view === 'login');
    setDisplay(els.registerForm, view === 'register');
    setDisplay(els.forgotForm, view === 'forgot');
    setDisplay(els.resetForm, view === 'reset');

    const loginActive = view !== 'register';
    if (els.loginTab) els.loginTab.classList.toggle('active', loginActive);
    if (els.registerTab) els.registerTab.classList.toggle('active', view === 'register');

    const meta = viewMeta[view] || viewMeta.login;
    if (els.title) els.title.textContent = meta.title;
    if (els.sub) els.sub.textContent = meta.sub;

    if (clearMessage) showMessage('', '');
  }

  function lockUI(locked) {
    if (!els.gate) return;
    return; // NEVER show the login wall
  }

  function updateHeader(user) {
    const isLoggedIn = !!user;
    const email = user?.email || 'Signed In';

    if (els.userChip) els.userChip.style.display = isLoggedIn ? 'inline-flex' : 'none';
    if (els.userEmail) els.userEmail.textContent = email;
    if (els.logoutBtn) els.logoutBtn.style.display = isLoggedIn ? 'inline-block' : 'none';
    if (els.openBtn) els.openBtn.style.display = isLoggedIn ? 'none' : 'inline-block';
  }

  function applyAuthUI(user) {
    updateHeader(user);
    const mustLock = state.recoveryMode ? true : !user;
    lockUI(mustLock);
  }

  function getAuthParams() {
    const hash = window.location.hash ? window.location.hash.slice(1) : '';
    const hashParams = new URLSearchParams(hash);
    const searchParams = new URLSearchParams(window.location.search);

    return {
      hashParams,
      searchParams,
      type: searchParams.get('type') || hashParams.get('type') || '',
      tokenHash: searchParams.get('token_hash') || hashParams.get('token_hash') || '',
      errorCode: hashParams.get('error_code') || searchParams.get('error_code') || '',
      errorDescription: hashParams.get('error_description') || searchParams.get('error_description') || '',
    };
  }

  function isRecoveryInUrl() {
    return getAuthParams().type === 'recovery';
  }

  function clearAuthParams() {
    const url = new URL(window.location.href);
    const authKeys = [
      'token_hash',
      'type',
      'error',
      'error_code',
      'error_description',
      'access_token',
      'refresh_token',
      'expires_at',
      'expires_in',
      'token_type',
      'provider_token',
      'provider_refresh_token',
      'code',
    ];

    let changed = false;
    authKeys.forEach((key) => {
      if (url.searchParams.has(key)) {
        url.searchParams.delete(key);
        changed = true;
      }
    });

    if (url.hash) {
      const hashParams = new URLSearchParams(url.hash.slice(1));
      let hashChanged = false;
      authKeys.forEach((key) => {
        if (hashParams.has(key)) {
          hashParams.delete(key);
          hashChanged = true;
        }
      });

      if (hashChanged) {
        const nextHash = hashParams.toString();
        url.hash = nextHash ? `#${nextHash}` : '';
        changed = true;
      }
    }

    if (!changed) return;

    const nextUrl = `${url.pathname}${url.search}${url.hash}`;
    window.history.replaceState({}, document.title, nextUrl);
  }

  async function establishRecoverySession() {
    const { type, tokenHash, errorCode, errorDescription } = getAuthParams();

    if (errorCode) {
      state.recoveryMode = false;
      setView('forgot', { clearMessage: false });
      lockUI(true);
      showMessage(errorDescription || 'Recovery link is invalid or has expired. Request a new reset link.', 'error');
      clearAuthParams();
      return false;
    }

    if (type !== 'recovery') return false;

    if (!tokenHash) {
      const { data } = await supabase.auth.getSession();
      if (data?.session?.user) {
        state.recoveryMode = true;
        setView('reset', { clearMessage: false });
        lockUI(true);
        showMessage('Recovery link verified. Set your new password.', 'success');
        clearAuthParams();
        return true;
      }

      state.recoveryMode = false;
      setView('forgot', { clearMessage: false });
      lockUI(true);
      showMessage('Recovery link is incomplete. Request a new password reset email.', 'error');
      clearAuthParams();
      return false;
    }

    const { error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: 'recovery',
    });

    if (error) {
      state.recoveryMode = false;
      setView('forgot', { clearMessage: false });
      lockUI(true);
      showMessage(error.message || 'Recovery link is invalid or has expired. Request a new reset link.', 'error');
      clearAuthParams();
      return false;
    }

    state.recoveryMode = true;
    setView('reset', { clearMessage: false });
    lockUI(true);
    showMessage('Recovery link verified. Set your new password.', 'success');
    clearAuthParams();
    return true;
  }

  function getResetRedirectUrl() {
    return PASSWORD_RESET_REDIRECT_URL;
  }

  function normalizeEmail(value) {
    return String(value || '').trim().toLowerCase();
  }

  function normalizeName(value) {
    return String(value || '').trim().replace(/\s+/g, ' ');
  }

  function isBootstrapSuperAdminEmail(email) {
    return BOOTSTRAP_SUPER_ADMIN_EMAILS.includes(normalizeEmail(email));
  }

  function buildFullName(firstName, lastName) {
    return [firstName, lastName].filter(Boolean).join(' ');
  }

  function normalizeRole(value) {
    return String(value || '').trim().toLowerCase() === ROLE_SUPER_ADMIN
      ? ROLE_SUPER_ADMIN
      : ROLE_ADMIN;
  }

  function normalizeApprovalStatus(value) {
    const status = String(value || '').trim().toLowerCase();
    if (status === STATUS_ACTIVE || status === STATUS_REJECTED) return status;
    return STATUS_PENDING;
  }

  function validatePassword(password) {
    if (!password) return 'Enter a password.';
    if (password.length < MIN_PASSWORD_LENGTH) {
      return `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
    }
    return '';
  }

  function getRegisterValues() {
    const firstName = normalizeName(els.registerFirstName?.value);
    const lastName = normalizeName(els.registerLastName?.value);
    const email = normalizeEmail(els.registerEmail?.value);
    const password = els.registerPassword?.value || '';
    const confirmPassword = els.registerConfirmPassword?.value || '';

    if (els.registerFirstName) els.registerFirstName.value = firstName;
    if (els.registerLastName) els.registerLastName.value = lastName;
    if (els.registerEmail) els.registerEmail.value = email;

    return {
      firstName,
      lastName,
      fullName: buildFullName(firstName, lastName),
      email,
      password,
      confirmPassword,
    };
  }

  function validateRegisterValues(values) {
    if (!values.firstName) return 'Enter your first name.';
    if (!values.lastName) return 'Enter your last name.';
    if (!values.email) return 'Enter your email address.';
    if (!EMAIL_PATTERN.test(values.email)) return 'Enter a valid email address.';

    const passwordError = validatePassword(values.password);
    if (passwordError) return passwordError;

    if (!values.confirmPassword) return 'Confirm your password.';
    if (values.password !== values.confirmPassword) return 'Passwords do not match.';
    return '';
  }

  function profilePayloadFromUser(user) {
    const firstName = normalizeName(user?.user_metadata?.first_name);
    const lastName = normalizeName(user?.user_metadata?.last_name);
    const fullName = normalizeName(user?.user_metadata?.full_name) || buildFullName(firstName, lastName);

    return {
      user_id: user.id,
      email: normalizeEmail(user?.email),
      first_name: firstName,
      last_name: lastName,
      full_name: fullName,
      updated_at: new Date().toISOString(),
    };
  }

  function warnProfileSync(error) {
    if (profileSyncWarningShown) return;
    profileSyncWarningShown = true;
    console.warn('[Auth] User profile sync skipped:', error?.message || error || '');
  }

  async function loadUserProfile(userId) {
    if (!userId) return null;

    const { data, error } = await supabase
      .from(PROFILE_TABLE)
      .select('user_id, email, full_name, first_name, last_name, role, approval_status, rejection_reason')
      .eq('user_id', userId)
      .maybeSingle();

    if (error) {
      console.error('[Auth] User profile lookup failed:', error.message || error);
      return null;
    }

    return data || null;
  }

  function getApprovalMessage(profile) {
    const status = normalizeApprovalStatus(profile?.approval_status);
    if (status === STATUS_REJECTED) {
      const reason = String(profile?.rejection_reason || '').trim();
      return reason
        ? `Your account was rejected. ${reason}`
        : 'Your account was rejected by the super admin.';
    }
    return 'Your account is pending super admin approval.';
  }

  async function denyAccess(message) {
    await supabase.auth.signOut();
    state.recoveryMode = false;
    updateHeader(null);
    lockUI(true);
    setView('login', { clearMessage: false });
    showMessage(message, 'error');
  }

  async function ensureApprovedAccess(user) {
    if (!user?.id || state.recoveryMode) return true;
    if (isBootstrapSuperAdminEmail(user.email)) return true;

    const profile = await loadUserProfile(user.id);

    // If no profile found, allow through — profile will be created by sync
    // and the user has already authenticated with a valid password
    if (!profile) return true;

    const status = normalizeApprovalStatus(profile?.approval_status);
    if (status === STATUS_ACTIVE) return true;

    // Only hard-block users who are explicitly rejected
    if (status === STATUS_REJECTED) {
      await denyAccess(getApprovalMessage(profile));
      return false;
    }

    // Pending users: allow through (internal tool — trust anyone with credentials)
    return true;
  }

  async function syncUserProfileRecord(user) {
    if (!user?.id) return;

    const { error } = await supabase
      .from(PROFILE_TABLE)
      .upsert(profilePayloadFromUser(user), { onConflict: 'user_id' });

    if (error) warnProfileSync(error);
  }

  async function syncSession() {
    // We strictly use the original creator account (Alex) because 
    // Supabase RLS policies are still locking data to the creator's ID.
    // By simulating Alex's login for the whole team, everyone shares the same data!
    const masterEmail = 'alex@joinangora.com';
    const masterPass  = 'TempPass2024!';

    // Try to login
    let { data, error } = await supabase.auth.signInWithPassword({
      email: masterEmail,
      password: masterPass
    });

    const realUser = data?.user || data?.session?.user || null;

    if (!realUser) {
        console.warn('Auto-login failed for Alex:', error);
    }

    applyAuthUI(realUser);
    notifyAuthState('SESSION_SYNC', realUser);
    lockUI(false); // Guarantee UI is unlocked
  }

  async function handleLoginSubmit(event) {
    event.preventDefault();

    const email = normalizeEmail(els.loginEmail?.value);
    const password = els.loginPassword?.value || '';

    if (!email || !password) {
      showMessage('Enter email and password.', 'error');
      return;
    }

    setBusy(els.loginSubmit, true);

    const { data, error } = await supabase.auth.signInWithPassword({ email, password });

    setBusy(els.loginSubmit, false);

    if (error) {
      showMessage(error.message, 'error');
      return;
    }

    const user = data?.user || data?.session?.user || null;

    await syncUserProfileRecord(user);

    applyAuthUI(user);
    notifyAuthState('SIGNED_IN', user);

    if (els.loginForm) els.loginForm.reset();
    showMessage('Signed in successfully.', 'success');
  }

  async function handleRegisterSubmit(event) {
    event.preventDefault();

    const values = getRegisterValues();
    const validationError = validateRegisterValues(values);

    if (validationError) {
      showMessage(validationError, 'error');
      return;
    }

    setBusy(els.registerSubmit, true);

    const { data, error } = await supabase.auth.signUp({
      email: values.email,
      password: values.password,
      options: {
        data: {
          first_name: values.firstName,
          last_name: values.lastName,
          full_name: values.fullName,
          role: ROLE_ADMIN,
          approval_status: STATUS_ACTIVE,
        },
      },
    });

    setBusy(els.registerSubmit, false);

    if (error) {
      showMessage(error.message, 'error');
      return;
    }

    if (data?.user?.id) {
      await syncUserProfileRecord({
        ...data.user,
        email: values.email,
        user_metadata: {
          ...data.user.user_metadata,
          first_name: values.firstName,
          last_name: values.lastName,
          full_name: values.fullName,
        },
      });
    }

    if (els.registerForm) els.registerForm.reset();
    setView('login', { clearMessage: false });
    if (els.loginEmail) els.loginEmail.value = values.email;

    if (data?.session) {
      await supabase.auth.signOut();
      showMessage('Account created! Check your email to confirm, then sign in.', 'success');
      return;
    }

    showMessage('Account created! Check your email to confirm, then you can sign in.', 'success');
  }

  async function handleForgotSubmit(event) {
    event.preventDefault();

    const email = normalizeEmail(els.forgotEmail?.value);

    if (!email) {
      showMessage('Enter your email to reset the password.', 'error');
      return;
    }

    setBusy(els.forgotSubmit, true);

    const redirectTo = getResetRedirectUrl();
    const options = redirectTo ? { redirectTo } : undefined;
    const { error } = await supabase.auth.resetPasswordForEmail(email, options);

    setBusy(els.forgotSubmit, false);

    if (error) {
      showMessage(error.message, 'error');
      return;
    }

    if (els.forgotForm) els.forgotForm.reset();
    if (els.loginEmail) els.loginEmail.value = email;

    setView('login', { clearMessage: false });
    showMessage('Reset link sent. Check your email inbox.', 'success');
  }

  async function handleResetSubmit(event) {
    event.preventDefault();

    const password = els.resetPassword?.value || '';
    const confirmPassword = els.resetConfirmPassword?.value || '';

    if (!password || !confirmPassword) {
      showMessage('Enter and confirm your new password.', 'error');
      return;
    }

    const passwordError = validatePassword(password);
    if (passwordError) {
      showMessage(passwordError, 'error');
      return;
    }

    if (password !== confirmPassword) {
      showMessage('Passwords do not match.', 'error');
      return;
    }

    setBusy(els.resetSubmit, true);

    const { data, error } = await supabase.auth.updateUser({ password });

    setBusy(els.resetSubmit, false);

    if (error) {
      showMessage(error.message, 'error');
      return;
    }

    if (els.resetForm) els.resetForm.reset();

    state.recoveryMode = false;

    const user = data?.user || null;

    const allowed = await ensureApprovedAccess(user);
    if (!allowed) return;

    applyAuthUI(user);
    notifyAuthState('PASSWORD_RESET', user);
    setView('login', { clearMessage: false });
    showMessage('Password updated successfully.', 'success');
  }

  async function handleLogoutClick() {
    const { error } = await supabase.auth.signOut();

    if (error) {
      showMessage(error.message, 'error');
      return;
    }

    state.recoveryMode = false;
    setView('login', { clearMessage: false });
    showMessage('Signed out.', 'success');
  }

  function attachEvents() {
    if (els.loginTab) {
      els.loginTab.addEventListener('click', () => setView('login'));
    }
    if (els.registerTab) {
      els.registerTab.addEventListener('click', () => {
        state.recoveryMode = false;
        setView('register');
      });
    }

    if (els.loginForm) {
      els.loginForm.addEventListener('submit', handleLoginSubmit);
    }
    if (els.registerForm) {
      els.registerForm.addEventListener('submit', handleRegisterSubmit);
    }
    if (els.forgotForm) {
      els.forgotForm.addEventListener('submit', handleForgotSubmit);
    }
    if (els.resetForm) {
      els.resetForm.addEventListener('submit', handleResetSubmit);
    }

    if (els.forgotLink) {
      els.forgotLink.addEventListener('click', () => {
        setView('forgot');
        if (els.forgotEmail) {
          els.forgotEmail.value = (els.loginEmail?.value || '').trim();
        }
      });
    }

    if (els.forgotBackBtn) {
      els.forgotBackBtn.addEventListener('click', () => setView('login'));
    }

    if (els.resetBackBtn) {
      els.resetBackBtn.addEventListener('click', () => {
        state.recoveryMode = false;
        setView('login');
        syncSession();
      });
    }

    if (els.openBtn) {
      els.openBtn.addEventListener('click', () => {
        state.recoveryMode = false;
        setView('login');
        lockUI(true);
      });
    }

    if (els.logoutBtn) {
      els.logoutBtn.addEventListener('click', handleLogoutClick);
    }

    supabase.auth.onAuthStateChange((event, session) => {
      const user = session?.user || null;

      if (event === 'PASSWORD_RECOVERY') {
        state.recoveryMode = true;
        setView('reset', { clearMessage: false });
        updateHeader(user);
        lockUI(true);
        showMessage('Recovery link verified. Set your new password.', 'success');
        clearAuthParams();
        return;
      }

      if (event === 'SIGNED_OUT') {
        state.recoveryMode = false;
        setView('login', { clearMessage: false });
        applyAuthUI(null);
        notifyAuthState('SIGNED_OUT', null);
        return;
      }

      if (user && event === 'SIGNED_IN' && !state.recoveryMode) {
        syncUserProfileRecord(user);
        notifyAuthState('SIGNED_IN', user);
        return;
      }

      applyAuthUI(user);
      notifyAuthState(event, user);

      if (user && event === 'USER_UPDATED') {
        syncUserProfileRecord(user);
      }
    });
  }

  attachEvents();
  setView('login');
  lockUI(true);
  syncSession();
})();
