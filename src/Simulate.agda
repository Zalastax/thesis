module Simulate where

open import Sublist using (_⊆_ ; [] ; keep ; skip ; All-⊆)
open import ActorMonad public
open import SimulationEnvironment
open import EnvironmentOperations

open import Data.Colist using (Colist ; [] ; _∷_)
open import Data.List using (List ; _∷_ ; [] ; map)
open import Data.List.All using (All ; _∷_ ; [] ; lookup) renaming (map to ∀map)
open import Data.Nat using (ℕ ; zero ; suc ; _≟_ ; _<_ ; s≤s)
open import Data.Nat.Properties using (≤-reflexive ; ≤-step)
open import Data.Product using (Σ ; _,_ ; _×_ ; Σ-syntax)
open import Data.Unit using (⊤ ; tt)

open import Relation.Binary.PropositionalEquality using (_≡_ ; refl ; sym ; cong)

open import Level using (Lift ; lift) renaming (suc to lsuc ; zero to lzero)
open import Coinduction using (∞ ; ♯_ ; ♭)

data ReceiveKind : Set where
  Nothing : ReceiveKind
  Value : ReceiveKind
  Reference : Name → ReceiveKind
  Dropped : ReceiveKind

data Trace : Set where
  Return : Name → Trace
  Bind : Trace → Trace
  BindDouble : Name → Trace -- If we encounter a bind and then a bind again...
  Spawn : (spawner : Name) → (spawned : Name) → Trace
  SendValue : (sender : Name) → (receiver : Name) → Trace
  SendReference : (sender : Name) → (receiver : Name) → (reference : Name) → Trace
  Receive : Name → ReceiveKind → Trace
  TLift : Name → Trace
  Self : Name → Trace

record EnvStep : Set₂ where
  field
    env : Env
    trace : Trace

private
  keepSimulating : Trace → Env → Colist EnvStep

open Actor
open ValidActor
open Env
open FoundReference

simulate : Env → Colist EnvStep
simulate env with (acts env) | (actorsValid env)
-- ===== OUT OF ACTORS =====
simulate env | [] | _ = []
simulate env | actor ∷ rest | _ with (act actor)
-- ===== Value =====
simulate env | actor ∷ rest | _ |
  Value val = keepSimulating (Return (name actor)) (dropTop env) -- Actor is done, just drop it
-- ===== Bind =====
simulate env | actor ∷ rest | _ | m >>= f with (♭ m)
-- ===== Bind Value =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  Value val = keepSimulating (Bind (Return (name actor))) env'
  where
    bindAct : Actor
    bindAct = replace-actorM actor (♭ (f val))
    bindActValid : ValidActor (store env) bindAct
    bindActValid = record { hasInb = hasInb valid ; points = points valid }
    env' : Env
    env' = replace-actors env (bindAct ∷ rest) (bindActValid ∷ restValid)
-- ===== Bind Bind =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  mm >>= g = keepSimulating (Bind (BindDouble (name actor))) env'
  where
    bindAct : Actor
    bindAct = replace-actorM actor (mm >>= λ x → ♯ (g x >>= f))
    bindActValid : ValidActor (store env) bindAct
    bindActValid = record { hasInb = hasInb valid ; points = points valid }
    env' : Env
    env' = replace-actors env (bindAct ∷ rest) (bindActValid ∷ restValid)
-- ===== Bind Spawn =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  Spawn {NewIS} {B} {_} {ceN} bm = keepSimulating (Spawn (name actor) (freshName env)) (topToBack env') -- move the spawned to the back, keepSimulating will move bindAct. This round-robin thing doesn't really matter yet...
  where
    newStoreEntry : NamedInbox
    newStoreEntry = (freshName env) , NewIS
    newStore : Store
    newStore = newStoreEntry ∷ store env
    newInb : Inbox
    newInb = record { IS = NewIS ; inb = [] ; name = freshName env }
    newAct : Actor
    newAct = record
               { IS = NewIS
               ; A = B
               ; references = []
               ; es = []
               ; esEqRefs = refl
               ; ce = ceN
               ; act = bm
               ; name = freshName env
               }
    newActValid : ValidActor newStore newAct
    newActValid = record { hasInb = zero ; points = [] }
    newIsFresh : NameFresh newStore (suc (freshName env))
    newIsFresh = s≤s (≤-reflexive refl) ∷ ∀map ≤-step (nameIsFresh env)
    newInbs=newStore : store env ≡ inboxesToStore (inbs env) → newStore ≡ inboxesToStore (newInb ∷ inbs env)
    newInbs=newStore refl = refl
    bindAct : Actor
    bindAct = add-reference actor newStoreEntry (♭ (f _))
    bindActValid : ValidActor newStore bindAct
    bindActValid = record {
      hasInb = suc {pr =
        sucHelper (hasInb valid) (nameIsFresh env)
        } (hasInb valid)
      ; points = zero ∷ ∀map (λ x₁ → suc {pr =
        sucHelper x₁ (nameIsFresh env)
        } x₁) (points valid) }
    env' : Env
    env' = record
             { acts = newAct ∷ bindAct ∷ rest
             ; blocked = blocked env
             ; inbs = newInb ∷ inbs env
             ; store = newStore
             ; inbs=store = newInbs=newStore (inbs=store env)
             ; freshName = suc (freshName env)
             ; actorsValid = newActValid ∷ bindActValid ∷ ∀map (ValidActorSuc (nameIsFresh env)) restValid
             ; blockedValid = ∀map (ValidActorSuc (nameIsFresh env)) (blockedValid env)
             ; messagesValid = [] ∷ ∀map (λ {inb} mv → messagesValidSuc {_} {inb} (nameIsFresh env) mv) (messagesValid env)
             ; nameIsFresh = newIsFresh
             }
-- ===== Bind send value =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  SendValue {ToIS = ToIS} canSendTo (Value x a) = keepSimulating (Bind (SendValue (name actor) (name foundTo))) withUnblocked
  where
    foundTo : FoundReference (store env) ToIS
    foundTo = lookupReference valid canSendTo
    bindAct : Actor
    bindAct = replace-actorM actor (♭ (f _))
    bindActValid : ValidActor (store env) bindAct
    bindActValid = record { hasInb = hasInb valid ; points = points valid }
    withM : Env
    withM = replace-actors env (bindAct ∷ rest) (bindActValid ∷ restValid)
    addMsg : Σ (List (NamedMessage ToIS)) (All (messageValid (store env))) →
              Σ (List (NamedMessage ToIS)) (All (messageValid (store env)))
    addMsg (messages , allValid) = (Value x a ∷ messages) , tt ∷ allValid
    withUpdatedInbox : Env
    withUpdatedInbox = updateInboxEnv withM (reference foundTo) addMsg
    withUnblocked : Env
    withUnblocked = unblockActor withUpdatedInbox (name foundTo)
-- ===== Bind send reference =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  SendReference {ToIS = ToIS} {FwIS = FwIS} canSendTo canForward (Reference x) = keepSimulating (Bind (SendReference (name actor) (name foundTo) (name foundFw))) withUnblocked
  where
    foundTo : FoundReference (store env) ToIS
    foundTo = lookupReference valid canSendTo
    foundFw : FoundReference (store env) FwIS
    foundFw = lookupReference valid canForward
    bindAct : Actor
    bindAct = replace-actorM actor (♭ (f _))
    bindActValid : ValidActor (store env) bindAct
    bindActValid = record { hasInb = hasInb valid ; points = points valid }
    withM : Env
    withM = replace-actors env (bindAct ∷ rest) (bindActValid ∷ restValid)
    addMsg : Σ (List (NamedMessage ToIS)) (All (messageValid (store env))) →
              Σ (List (NamedMessage ToIS)) (All (messageValid (store env)))
    addMsg (messages , allValid) = (Reference x (name foundFw) ∷ messages) , ((reference foundFw) ∷ allValid)
    withUpdatedInbox : Env
    withUpdatedInbox = updateInboxEnv withM (reference foundTo) addMsg
    withUnblocked : Env
    withUnblocked = unblockActor withUpdatedInbox (name foundTo)
-- ===== Bind receive =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  Receive = keepSimulating (Bind (Receive (name actor) (receiveKind (Σ.proj₁ mInb)))) (env' mInb)
  where
    mInb : Σ[ ls ∈ List (NamedMessage (IS actor)) ] All (messageValid (store env)) ls
    mInb = getInbox env (hasInb valid)
    myPoint : (inboxesToStore (inbs env) ≡ store env) → (name actor) ↦ (IS actor) ∈e inboxesToStore (inbs env)
    myPoint refl = hasInb valid
    removeMsg : Σ[ inLs ∈ List (NamedMessage (IS actor))] All (messageValid (store env)) inLs → Σ[ outLs ∈ List (NamedMessage (IS actor))] All (messageValid (store env)) outLs
    removeMsg ([] , []) = [] , []
    removeMsg (x ∷ inls , px ∷ prfs) = inls , prfs
    inboxesAfter : Σ[ ls ∈ List Inbox ] All (allMessagesValid (store env)) ls × (inboxesToStore (inbs env) ≡ inboxesToStore ls)
    inboxesAfter = updateInboxes {name actor} {IS actor} (store env) (inbs env) (messagesValid env) (myPoint (sym (inbs=store env))) removeMsg
    -- I would like to not use rewrite, but I couldn't get something Agda liked working
    sameStoreAfter : store env ≡ inboxesToStore (Σ.proj₁ inboxesAfter)
    sameStoreAfter rewrite (sym (Σ.proj₂ (Σ.proj₂ inboxesAfter))) = Env.inbs=store env
    receiveKind : List (NamedMessage (IS actor)) → ReceiveKind
    receiveKind [] = Nothing
    receiveKind (Value _ _ ∷ ls) = Value
    receiveKind (Reference _ refName ∷ ls) = Reference refName
    env' : Σ[ ls ∈ List (NamedMessage (IS actor)) ] All (messageValid (Env.store env)) ls → Env
    env' ([] , proj₂) = replace-actors+blocked env rest restValid (actor ∷ blocked env) (valid ∷ blockedValid env)
    env' (Value x a ∷ proj₁ , proj₂) = record
                                      { acts = replace-actorM actor (♭ (f (Value x a)))∷ rest
                                      ; blocked = Env.blocked env
                                      ; inbs = Σ.proj₁ inboxesAfter
                                      ; store = Env.store env
                                      ; inbs=store = sameStoreAfter
                                      ; freshName = Env.freshName env
                                      ; actorsValid = record { hasInb = hasInb valid ; points = points valid } ∷ restValid
                                      ; blockedValid = Env.blockedValid env
                                      ; messagesValid = Σ.proj₁ (Σ.proj₂ inboxesAfter)
                                      ; nameIsFresh = Env.nameIsFresh env
                                      }
    env' (Reference {Fw} x fwName ∷ proj₁ , px ∷ proj₂) = record
                                         { acts = add-reference actor (fwName , Fw) (♭ (f (Reference x))) ∷ rest
                                         ; blocked = Env.blocked env
                                         ; inbs = Σ.proj₁ inboxesAfter
                                         ; store = Env.store env
                                         ; inbs=store = sameStoreAfter
                                         ; freshName = Env.freshName env
                                         ; actorsValid = record { hasInb = hasInb valid ; points = px ∷ points valid } ∷ restValid
                                         ; blockedValid = Env.blockedValid env
                                         ; messagesValid = Σ.proj₁ (Σ.proj₂ inboxesAfter)
                                         ; nameIsFresh = Env.nameIsFresh env
                                         }
-- ===== Bind lift =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  ALift {B} {esX} {ceX} inc x with (♭ x)
... | bx = keepSimulating (Bind (TLift (name actor))) env'
  where
    liftedRefs = liftRefs inc (references actor) (esEqRefs actor)
    liftedBx : ActorM (IS actor) B (map justInbox (Σ.proj₁ liftedRefs)) ceX
    liftedBx rewrite (sym (Σ.proj₂ (Σ.proj₂ liftedRefs))) = bx
    bindAct : Actor
    bindAct = record
                { IS = IS actor
                ; A = A actor
                ; references = Σ.proj₁ liftedRefs
                ; es = map justInbox (Σ.proj₁ liftedRefs)
                ; esEqRefs = refl
                ; ce = ce actor
                ; act = ♯ liftedBx >>= f
                ; name = name actor
                }
    bindActValid : ValidActor (store env) bindAct
    bindActValid = record { hasInb = hasInb valid ; points = All-⊆ (Σ.proj₁ (Σ.proj₂ liftedRefs)) (points valid) }
    env' : Env
    env' = replace-actors env (bindAct ∷ rest) (bindActValid ∷ restValid)
-- ===== Bind self =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid | m >>= f |
  Self = keepSimulating (Bind (Self (name actor))) env'
  where
    bindAct : Actor
    bindAct = add-reference actor (name actor , IS actor) (♭ (f _))
    bindActValid : ValidActor (store env) bindAct
    bindActValid = record { hasInb = hasInb valid ; points = hasInb valid ∷ points valid }
    env' : Env
    env' = replace-actors env (bindAct ∷ rest) (bindActValid ∷ restValid)
-- ===== Spawn =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid |
  Spawn act₁ = keepSimulating (Spawn (name actor) (freshName env)) (addTop act₁ (dropTop env))
-- ===== Send value =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid |
  SendValue {ToIS = ToIS} canSendTo (Value x a ) = keepSimulating (SendValue (name actor) (name foundTo)) withUnblocked
  where
    foundTo : FoundReference (store env) ToIS
    foundTo = lookupReference valid canSendTo
    addMsg : Σ (List (NamedMessage ToIS)) (All (messageValid (store env))) →
      Σ (List (NamedMessage ToIS)) (All (messageValid (store env)))
    addMsg (messages , allValid) = (Value x a ∷ messages) , tt ∷ allValid
    withUpdatedInbox : Env
    withUpdatedInbox = updateInboxEnv env (reference foundTo) addMsg
    withTopDropped : Env
    withTopDropped = dropTop withUpdatedInbox
    withUnblocked : Env
    withUnblocked = unblockActor withTopDropped (name foundTo)
-- ===== Send reference =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid |
  SendReference {ToIS = ToIS} {FwIS = FwIS} canSendTo canForward (Reference x) = keepSimulating (SendReference (name actor) (name foundTo) (name foundFw)) withUnblocked
  where
    foundTo : FoundReference (store env) ToIS
    foundTo = lookupReference valid canSendTo
    foundFw : FoundReference (store env) FwIS
    foundFw = lookupReference valid canForward
    addMsg : Σ (List (NamedMessage ToIS)) (All (messageValid (store env))) →
      Σ (List (NamedMessage ToIS)) (All (messageValid (store env)))
    addMsg (messages , allValid) = (Reference x (name foundFw) ∷ messages) , (reference foundFw) ∷ allValid
    withUpdatedInbox : Env
    withUpdatedInbox = updateInboxEnv env (reference foundTo) addMsg
    withTopDropped : Env
    withTopDropped = dropTop withUpdatedInbox
    withUnblocked : Env
    withUnblocked = unblockActor withTopDropped (name foundTo)
-- ===== Receive =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid |
  Receive = keepSimulating (Receive (name actor) Dropped) (dropTop env) -- Receive without follow up is like return, just drop it.
  -- If we care about what state the inboxes end up in, then we need to actually do something here
-- ===== Lift =====
simulate env | actor@(_) ∷ rest | valid ∷ restValid |
  ALift inc x with (♭ x)
... | bx = keepSimulating (TLift (name actor)) env'
  where
    liftedRefs = liftRefs inc (references actor) (esEqRefs actor)
    -- TODO: See if we can avoid using rewrite here
    liftedBx : ActorM (IS actor) (A actor) (map justInbox (Σ.proj₁ liftedRefs)) (ce actor)
    liftedBx rewrite (sym (Σ.proj₂ (Σ.proj₂ liftedRefs))) = bx
    bxAct : Actor
    bxAct = record
              { IS = IS actor
              ; A = A actor
              ; references = Σ.proj₁ liftedRefs
              ; es = map justInbox (Σ.proj₁ liftedRefs)
              ; esEqRefs = refl
              ; ce = ce actor
              ; act = liftedBx
              ; name = name actor
              }
    bxValid : ValidActor (Env.store env) bxAct
    bxValid = record { hasInb = hasInb valid ; points = All-⊆ (Σ.proj₁ (Σ.proj₂ liftedRefs)) (points valid) }
    env' : Env
    env' = replace-actors env (bxAct ∷ rest) (bxValid ∷ restValid)
simulate env | actor@(_) ∷ rest | valid ∷ restValid |
  Self = keepSimulating (Self (name actor)) (dropTop env)


keepSimulating trace env = record { env = env ; trace = trace } ∷ ♯ simulate (topToBack env)