import { BlsBn254, kyberMarshalG2 } from '../src'

// yarn bls:newkey

async function main() {
    const bls = await BlsBn254.create()
    const { pubKey, secretKey, _secretKey } = bls.createKeyPair()
    console.log(
        JSON.stringify(
            {
                secretKey,
                _secretKey,
                pubKey: kyberMarshalG2(pubKey),
            },
            null,
            4,
        ),
    )
}

main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
