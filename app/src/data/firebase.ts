// Firebase set-up for the V2 project. Config comes from VITE_FIREBASE_* env vars
// (.env.development for the local emulators; the V2 project's web config for production).
// There is deliberately no reference to the V1 project here.
import { initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectDataConnectEmulator, getDataConnect } from 'firebase/data-connect';

const env = import.meta.env;
const required = ['VITE_FIREBASE_API_KEY', 'VITE_FIREBASE_AUTH_DOMAIN', 'VITE_FIREBASE_PROJECT_ID', 'VITE_FIREBASE_APP_ID'] as const;
export const missingConfig = required.filter(k => !env[k]);

export const app = initializeApp({
  apiKey: env.VITE_FIREBASE_API_KEY,
  authDomain: env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: env.VITE_FIREBASE_PROJECT_ID,
  appId: env.VITE_FIREBASE_APP_ID,
});

export const auth = getAuth(app);

// Must match dataconnect/dataconnect.yaml and dataconnect/connector/connector.yaml
export const dataConnect = getDataConnect(app, {
  connector: 'door-scheduler',
  service: 'door-scheduler',
  location: 'europe-west2',
});

export const usingEmulators = env.VITE_USE_EMULATORS === 'true';
if (usingEmulators) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectDataConnectEmulator(dataConnect, '127.0.0.1', 9399);
}
