// End-to-end check against a running stack (`docker compose up`): two players sign in, share a lobby, the host
// starts it, both receive the game-server address and a ticket and are welcomed by the game server.
import { api, connect, signIn } from "../src/client.ts";

const base = process.env.BACKEND_URL ?? "http://localhost:3000";
// Under compose the game server's public URL is what the ticket response says; locally that is the host port.
const rewrite = (url: string): string => url.replace(process.env.E2E_REWRITE_FROM ?? "\u0000", process.env.E2E_REWRITE_TO ?? "");

for (let attempt = 0; ; attempt++) {
  const ready = await fetch(`${base}/ready`).then((r) => r.json() as Promise<{ gameServers?: number }>).catch(() => null);
  if (ready?.gameServers) break;
  if (attempt > 30) throw new Error("backend has no live game server");
  await new Promise((resolve) => setTimeout(resolve, 1000));
}

const alice = await signIn(base, "stub:1001:alice");
const bob = await signIn(base, "stub:1002:bob");
const lobby = await api.createLobby(base, alice, { maxPlayers: 4 });
await api.joinByCode(base, bob, lobby.code);
await api.start(base, alice, lobby.id);

for (const player of [alice, bob]) {
  const { address, ticket, matchId } = await api.ticket(base, player, lobby.id);
  const welcome = await connect(rewrite(address.url), ticket);
  if (welcome.type !== "welcome" || welcome.matchId !== matchId || welcome.userId !== player.userId) {
    throw new Error(`unexpected welcome: ${JSON.stringify(welcome)}`);
  }
  console.log(`${player.name}: ${JSON.stringify(welcome)}`);
}
console.log("e2e ok");
