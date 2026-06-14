import { JsonRpcProvider, Wallet } from 'ethers'

async function main() {
  const rpcUrl = process.env.RPC_URL!
  const provider = new JsonRpcProvider(rpcUrl)
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider)

  console.log('RPC:', rpcUrl)
  console.log('Wallet:', wallet.address)

  const { createCofheConfig, createCofheClient } = await import('@cofhe/sdk/node')
  const { Encryptable } = await import('@cofhe/sdk')
  const { arbSepolia } = await import('@cofhe/sdk/chains')
  const { Ethers6Adapter } = await import('@cofhe/sdk/adapters')

  console.log('Building Ethers6Adapter...')
  const { publicClient, walletClient } = await Ethers6Adapter(provider, wallet)

  console.log('Creating cofhe client...')
  const client = createCofheClient(createCofheConfig({ supportedChains: [arbSepolia] }))

  console.log('Connecting to coprocessor...')
  await client.connect(publicClient, walletClient)

  console.log('Encrypting [address, uint64=100000000]...')
  const start = Date.now()
  const [encAddress, encAmount] = await client
    .encryptInputs([Encryptable.address(wallet.address), Encryptable.uint64(100000000n)])
    .execute()
  const elapsed = Date.now() - start

  const fmt = (v: any) =>
    JSON.stringify(v, (_k, x) => (typeof x === 'bigint' ? x.toString() : x), 2)
  console.log(`\nEncryption took ${elapsed}ms`)
  console.log('encAddress.ctHash:', (encAddress as any).ctHash?.toString?.())
  console.log('encAmount.ctHash: ', (encAmount as any).ctHash?.toString?.())
  console.log('encAmount.utype:  ', (encAmount as any).utype)
  console.log('encAmount.signature length:', (encAmount as any).signature?.length)

  console.log('\nSmoke PASSED: FHE init + encrypt round-trip OK against Arb Sepolia coprocessor')
}

main().catch((err) => {
  console.error('Smoke FAILED:', err?.message ?? err)
  if (err?.cause) console.error('cause:', err.cause?.message ?? err.cause)
  process.exit(1)
})
