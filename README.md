# Backer

Backer is a web3 version of Patreon. Offer memberships and get paid via real-time streams of crypto. In return, your Backers receive a real-time stream of your very own ERC20 token. Backers also get an NFT key from Unlock Protocol that can be used to grant access to members-only benefits. Setup takes minutes. Get paid and build a community of Backers.

## Features
- Create your own ERC20 token with pre-minted supply
- Choose the token you want to be paid in (ie. DAI)
- Create multiple memberships tiers. Backers choose a tier with a monthly rate but pay through real-time money streams using the Superfluid Protocol. Get paid every second.
- Active Backers get your token streamed to them in real-time. Each tier defines a multiplier that determines how many tokens they receive. For example, a stream of 5 DAI per month for a tier with a multiplier of 2 will receive 10 tokens per month, streamed in real-time.
- When Backers cancel their stream, the token stream automatically stops immediately, and the Unlcok key is revoked
- Create a profile page with that displays information, images, links, and your tiers. Send prospective Backers to your profile page so thay can back you.
- Admin dashboard includes stats, graphs, member list and forms for adding tiers, editing profile, adding team members, withdrawing funds, and granting tokens.

## How it was built
- A factory contract deploys an implementation of Backer contract logic.
- Via the dapp UI, a creator can deploy their own clone/proxy Backer contract.
- The backer contract enables the creation of membership tiers with distinct pricing and rewards.
- Each tier deploys a Lock contract using Unlock Protocol. If a creator has three tiers, they have 3 Locks.
- Creators can add profile data. Profile data, including images, are stored on IPFS using nft.storage. The IPFS cid is stored in the Backer contract. The public profile page includes an avatar image, cover image, name, description, and cards for each of the tiers. Backers can use JOIN buttons to start streaming funds.
- The Backer contract is a Super App using the Superfluid protocol. It receives and reacts to callbacks when streams to the contract are started and stopped.
- When a backer joins -- starts streaming to the Backer contract -- the Backer contract reacts to the new stream by open a seperate stream of the creator's ERC20 token, from the contract to the Backer. The "multiplier" defined in the tier determines the flow rate. For example a tier with a prices of 10 DAI per month and a multiplier of 10 would stream 100 tokens to the backer per month. The token balance updates in real-time in the Backer's wallet, updating every second.
- Also, when a backer joins, a call is made to the Lock contract (deployed earlier for each tier via Unlock Protocol) to grant a key to the backer. The key is an ERC721 NFT that denotes their membership in the tier/lock. The key can be used to unlock various members-only benefits, including private Discord channels and more.
- When a Backer cancels -- when they stop streaming towards the contract -- the Backer contract reacts to this and immediately stops the stream of ERC20 tokens to the (former) Backer.
- Also when a Backer cancels, a task is added a job queue stored in the backer contract, to cancel the Lock key owned by the backer.
- A task created on the Gelato Network checks the job queue and exceutes a function to run the task to cancel the keys. As part of this task, the Backer contact calls the Lock contract to cancel the key, which is done by effectively setting the expiration date of the key, to the current time, immediately expiring it.
- The `Dashboard` screen of the dapp shows a graph of money streams and statistics for balance, current daily flowrate, Monthly Recurring Revenue (MRR), the total of ERC20 tokens that have been distributed and the total remaining supply
- The `Members` screen shows a list of Backers with start and end dates, tier, revenue to date, and the total of Backer ERC20 tokens in their wallet (keeping in mind that Backers are free to sell or send their tokens after receiving them). The list can be easily sorted and filtered: easily identify the HODLers and OGs.
- The `Tiers` screen lists the current tiers and enables the creator to add tiers, choosing a name, price, and multiplier for each.
- The `Profile` screen provides a form for saving profile date: name, description, social links, and images for avatar, cover images, and an image for the creator's token. This screen also enables a preview of the public profile screen, which will be shown to potential Backers, enabling them to back the creator by joining a tier. Images and text-based profile data are stored on the IPFS / Filecoin network via the nft.storage service -- only the IPFS cid hash is stored in the Backer contract for later retrieval.
- The `Balance` screen enables the creator to withdraw accumulated funds from the Backer contract. A withdrawal fee to the Backer Protocol is being considered here, but not currently implemented.
- The `TOKEN` screen enables the creator to grant (send) some of their ERC20 tokens to any address. Currently these are transferred immediately, not streamed.
- The `NFTs` screen (in future) will enable the easy creation of NFT collections and minting of ERC721 NFTs.
- The dapp is hosted on IPFS, deployed using a Github Action via Pinata. The IPFS cid is then served via Cloudflare's IPFS gateway using DNSLink, making the dapp accessible via https://backer.vip

## Next steps
- Development of NFTs feature
- UI for browsing creators using Backer (the Backer Factory contract keeps a registry, but no UI yet)
- Polygon launch

## Try it
- https://backer.vip

## Connect
- https://discord.gg/zMW8rkQtsN
- https://twitter.com/mthacks