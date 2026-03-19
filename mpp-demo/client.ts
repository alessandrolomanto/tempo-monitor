import { Mppx, tempo } from "mppx/client";
import { createPublicClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { tempoLocalnet } from "viem/chains";

const RPC_URL = process.env.RPC_URL || "http://localhost:8545";
const PRIVATE_KEY = process.env.BOB_PK || process.env.MPPX_PRIVATE_KEY;

if (!PRIVATE_KEY) {
  console.error("Set BOB_PK or MPPX_PRIVATE_KEY env var");
  process.exit(1);
}

const client = createPublicClient({
  chain: tempoLocalnet,
  transport: http(RPC_URL),
});

const mppx = Mppx.create({
  methods: [
    tempo.charge({
      account: privateKeyToAccount(PRIVATE_KEY as `0x${string}`),
      getClient: () => client,
    }),
  ],
  polyfill: false,
});

const SERVER_URL = process.env.SERVER_URL || "http://localhost:3030";

const res = await mppx.fetch(`${SERVER_URL}/api/joke`);
console.log("Status:", res.status);
console.log("Receipt:", res.headers.get("payment-receipt") ? "yes" : "no");
console.log("Body:", await res.json());
