import { Zap, Diamond, FlaskConical, Users, type LucideIcon } from 'lucide-react';
import { RESOURCE_IDS, RESOURCE_CATALOG, type Resource } from '../shared/resources';
const icons: Record<string, LucideIcon> = { Zap, Diamond, FlaskConical, Users };
export const resourceIcons = Object.fromEntries(
  RESOURCE_IDS.map((id) => [id, icons[RESOURCE_CATALOG[id].icon] ?? Diamond]),
) as Record<Resource, LucideIcon>;
