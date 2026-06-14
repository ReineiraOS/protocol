import { JsonRpcProvider, Wallet } from 'ethers'

async function main() {
  const rpcUrl = process.env.RPC_URL ?? 'https://arbitrum-sepolia-rpc.publicnode.com'
  const provider = new JsonRpcProvider(rpcUrl)
  const wallet = Wallet.createRandom().connect(provider)

  console.log('RPC:', rpcUrl)
  console.log('Smoke wallet (random, no funds needed):', wallet.address)

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

  console.log('Encrypting [address, uint64]...')
  const [encAddress, encAmount] = await client
    .encryptInputs([Encryptable.address(wallet.address), Encryptable.uint64(1000000n)])
    .execute()

  console.log('\n--- ENCRYPTED OUTPUTS ---')
  console.log(
    'encAddress:',
    JSON.stringify(encAddress, (_k, v) => (typeof v === 'bigint' ? v.toString() : v), 2),
  )
  console.log(
    'encAmount: ',
    JSON.stringify(encAmount, (_k, v) => (typeof v === 'bigint' ? v.toString() : v), 2),
  )

  console.log('\nSmoke test PASSED: FHE init + encrypt round-trip OK')
}

main().catch((err) => {
  console.error('Smoke test FAILED:', err)
  process.exit(1)
})
