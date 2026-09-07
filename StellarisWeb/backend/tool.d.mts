export const root: string;
export function cliAsync(args: string[]): Promise<string>;
export function cli(args: string[], options?: { stdio?: 'inherit' }): string;
