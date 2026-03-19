import { Hono } from "hono";
import { Mppx, tempo } from "mppx/hono";
import { createPublicClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { tempoLocalnet } from "viem/chains";

const RPC_URL = process.env.RPC_URL || "http://10.0.0.1:8545";

const app = new Hono();

const client = createPublicClient({
  chain: tempoLocalnet,
  transport: http(RPC_URL),
});

const feePayer = process.env.FEE_PAYER_KEY
  ? privateKeyToAccount(process.env.FEE_PAYER_KEY as `0x${string}`)
  : undefined;

const mppx = Mppx.create({
  secretKey: process.env.MPP_SECRET_KEY || "mpp-demo-local-devnet-secret",
  methods: [
    tempo.charge({
      getClient: () => client,
      ...(feePayer && { feePayer }),
    }),
  ],
});

app.get("/api/ping", (c) => c.json({ pong: true }));

app.get(
  "/api/joke",
  mppx.charge({
    amount: "0.01",
    currency: "0x20c0000000000000000000000000000000000000",
    recipient: "0x594DedC97A2c915a359090E06455442d1d66349f",
  }),
  (c) =>
    c.json({
      joke: "Why do programmers prefer dark mode? Because light attracts bugs.",
    }),
);

export default { port: 3030, fetch: app.fetch };
