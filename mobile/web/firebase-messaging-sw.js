/*
 * Firebase Messaging service worker for Veyra Web.
 * Replace the values below with the same public Firebase Web app configuration
 * used by the Flutter build. These are public client settings, not service-account
 * credentials. Never put a service-account JSON or private key in this file.
 */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCRFq0XCTDOG_oikRqqGM6DB2fSp9VHMwg',
  authDomain: 'chat-70649.firebaseapp.com',
  projectId: 'chat-70649',
  messagingSenderId: '885470479377',
  appId: '1:885470479377:web:dbe3f4818aa21ef04a9db0'
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'Veyra';
  const options = {
    body: payload.notification?.body || 'You have a new message in Veyra.',
    data: payload.data || {},
    tag: `veyra-${payload.data?.conversation_id || 'message'}`
  };
  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
    for (const client of windows) {
      if ('focus' in client) return client.focus();
    }
    if (clients.openWindow) return clients.openWindow('/');
    return undefined;
  }));
});
