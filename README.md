# Term Dai

Term Dai allows users to lockup their Dai for a fixed term in exchange for a fixed discount to hold their Term Dai balance until maturity, after which it can be burnt for an equal amount of Dai. Dai balance stays locked until maturity timestamp is past.

## Design

### Token Agnostic

Can be setup with Dai natively or Savings Dai. Governance has two deployment options:

- Create Term Dai(tDai) which offers a combined fixed rate which would include a fixed savings rate plus a fixed term lockup rate.
- Create Term Savings Dai(tsDai) which offers a fixed lockup rate over the underlying variable savings rate.

### Balances

Term Dai contract can hold the balance amounts for all the maturity dates. Balances with the same maturity date continue to be fungible and can be transferred to another address.

### Full Backing

Term Dai contract always holds an equal amount of Dai within it for Term Dai balances issued at all maturity timestamps. Discount portion of the Dai balance is transferred from Vat using the suck() function through Gate upfront during issuance to ensure its future obligations are not linked to a future state of the surplus buffer.

### Issuance

Governance sets isssuance parameters for a specific duration. Ex: Issuance size of 20MM Dai and Discount of 3% for a duration of 30 days.
Users can choose to lock Dai in the Term Dai contract in exchange for the discount upfront and a full payment in Dai after maturity timestamp. Ex: At issuance, user sends 97K Dai and receives 100K tDai with maturity timestamp set 30 days from now. Term Dai contract receives 97K from the user, 3K from the surplus buffer, and will hold 100K Dai until maturity.

### Redemption

Term Dai holder can redeem their balance for an equal amount of Dai only after the maturity date of their balance is past. Ex: At maturity, user can exchange their 100K tDai balance for 100K Dai.

### Issuance and Redemption Feature Extensions

Core contract can be extended with feature extension contracts to enable other novel forms of issuance, redemption, or combination of both as desired by governance and users.

Examples of feature extensions:

#### Standard Maturity Timestamp

Issuance extension contract can be deployed to dynamically calculate a discount to allow Dai holders to issue their Term Dai balance anytime at a standard maturity date to preseve fungibility.

#### Early Redemption Penalty

Early Redemption extension contract can be deployed to allow Term Dai holders to redeem their balance early by paying governance a certain amount.

#### Term Dai Maturity Rollover

Rollover extension contract can allow Term Dai holders to extend their maturity date well before its expiry according to parameters set by governance.

## Incentives

Governance can pay Dai holders a fixed amount to incentivize them to monitor the long term health of Dai and its backing with Term Dai.
