import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './App';
import './styles.css';
import './colonies.css';

const BackendLab = React.lazy(() =>
  import('./BackendLab').then((module) => ({ default: module.BackendLab })),
);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {location.pathname === '/lab' ? (
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
