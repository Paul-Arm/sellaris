import { useEffect, useState } from 'react';
import type { Client } from '../backend/client';
import { systemSubscription } from '../backend/system-subscription';
import { objectBodies, type StoredBody } from '../shared/systemObjects';
import { watchTables } from '../backend/projection-cache';

export function useSystemObjects(client: Client | null, externalId: string) {
  const [state, setState] = useState<{ key: string; bodies: StoredBody[] | null; error: string }>({
    key: '',
    bodies: null,
    error: '',
  });
  useEffect(() => {
    if (!client) return;
    let stopped = false,
      ready = false;
    const system = [...client.conn.db.gameAtlas.iter()].find((s) => s.externalId === externalId);
    if (!system) return;
    const update = () => {
      if (stopped || !ready) return;
      setState({
        key: externalId,
        bodies: objectBodies(
          [...client.conn.db.focusedSystemObjects.iter()].filter((r) => r.systemId === system.id),
        ),
        error: '',
      });
    };
    const table = client.conn.db.focusedSystemObjects;
    const unwatch = watchTables([table], update);
    void systemSubscription(client)
      .focus(system.id)
      .then(() => {
        ready = true;
        update();
      })
      .catch((e) => {
        if (!stopped) setState({ key: externalId, bodies: null, error: String(e) });
      });
    return () => {
      stopped = true;
      unwatch();
      void systemSubscription(client)
        .focus(0)
        .catch(() => {});
    };
  }, [client, externalId]);
  return state.key === externalId ? state : { bodies: null, error: '' };
}
