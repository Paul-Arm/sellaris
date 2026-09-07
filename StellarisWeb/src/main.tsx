import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './App';
import './styles.css';
import './colonies.css';

const BackendLab = React.lazy(() =>
  import('./BackendLab').then((module) => ({ default: module.BackendLab })),
);
const ModelHangar = React.lazy(() => import('./ModelHangar').then((m) => ({ default: m.ModelHangar })));
const AdminPanel = React.lazy(() => import('./AdminPanel').then((m) => ({ default: m.AdminPanel })));

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {location.pathname === '/admin' ? (
      <React.Suspense fallback={<div style={{ padding: 40 }}>Admin-Panel wird geladen …</div>}>
        <AdminPanel />
      </React.Suspense>
    ) : location.pathname === '/models' ? (
      <React.Suspense fallback={<div style={{ padding: 40 }}>Designhangar wird geladen …</div>}>
        <ModelHangar />
      </React.Suspense>
    ) : location.pathname === '/lab' ? (
      <React.Suspense
        fallback={<div style={{ padding: 40, color: '#91b6ad' }}>Backend-Labor wird geladen …</div>}
      >
        <BackendLab />
      </React.Suspense>
    ) : (
      <App />
    )}
  </React.StrictMode>,
);
