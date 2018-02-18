module Runtime where
open import Simulate
open import SimulationEnvironment

open import Data.Colist using (Colist ; [] ; _∷_)
open import Data.List using (List ; _∷_ ; [] ; map ; length)
open import Data.Nat using (ℕ ; zero ; suc)
open import Data.Nat.Show using (show)
open import Data.String using (String ; _++_)
open import Data.Unit using (⊤ ; tt)

open import Coinduction using (∞ ; ♯_ ; ♭)
import IO

Logger = (ℕ → EnvStep → IO.IO ⊤)

-- run-env continously runs the simulation of an environment
-- and transforms the steps taken into output to the console.
-- The output can be configured by prodiving different loggers.
run-env : Logger → Env → IO.IO ⊤
run-env logger env = loop 1 (simulate env)
  where
    loop : ℕ → Colist EnvStep → IO.IO ⊤
    loop n [] = IO.putStrLn ("Done after " ++ (show n) ++ " steps.")
    loop n (x ∷ xs) = ♯ logger n x IO.>> ♯ loop (suc n) (♭ xs)

open EnvStep
open Env

-- Creates a nicely formatted string out of a step-trace from the simulation
show-trace : Trace → String
show-trace (Return name) = show name ++ " returned"
show-trace (Bind trace) = "Bind [ " ++ show-trace trace ++ " ]"
show-trace (BindDouble name) = "Bind " ++ (show name)
show-trace (Spawn spawner spawned) = (show spawner) ++ " spawned " ++ (show spawned)
show-trace (SendValue sender receiver) = (show sender) ++ " sent a value to " ++ (show receiver)
show-trace (SendReference sender receiver reference) = (show sender) ++ " sent a reference to " ++ (show receiver) ++ " forwarding " ++ (show reference)
show-trace (Receive name Nothing) = (show name) ++ " received nothing. It was put in the blocked list"
show-trace (Receive name Value) = (show name) ++ " received a value"
show-trace (Receive name (Reference reference)) = (show name) ++ " received a reference to " ++ (show reference)
show-trace (Receive name Dropped) = (show name) ++ " received something, but had no bind. It was dropped"
show-trace (TLift name) = (show name) ++ " was lifted"
show-trace (Self name) = (show name ++ " used self")

-- Output the string of the trace for this step
log-trace : Trace → IO.IO ⊤
log-trace trace = IO.putStrLn (show-trace trace ++ ".")

-- Output the number of inboxes in the environment.
log-inbox-count : List Inbox → IO.IO ⊤
log-inbox-count inboxes = IO.putStrLn ("There are " ++ (show (Data.List.length inboxes)) ++ " inboxes.")

-- Output the number of messages in an inbox
log-message-counts : List Inbox → IO.IO ⊤
log-message-counts [] = IO.return _
log-message-counts (x ∷ xs) = ♯ IO.putStrLn ("Inbox #" ++ show (Inbox.name x) ++ " has " ++ (show (Data.List.length (Inbox.inbox-messages x))) ++ " messages.") IO.>> ♯ log-message-counts xs

-- Output the nunmber of inboxes and how many messages are in each inbox.
log-inboxes : List Inbox → IO.IO ⊤
log-inboxes inboxes = ♯ log-inbox-count inboxes IO.>> ♯ log-message-counts inboxes

-- Output how many actors are currently running and how many actors are blocked.
log-actors+blocked : Env → IO.IO ⊤
log-actors+blocked env = IO.putStrLn ("[A : " ++ show (length (acts env)) ++ " , B : " ++ show (length (blocked env)) ++ "]")

-- Count the number of steps taken
count-logger : Logger
count-logger n step = IO.putStrLn ((show n))

trace-logger : Logger
trace-logger n step = log-trace (trace step)

trace+inbox-logger : Logger
trace+inbox-logger n step = ♯ trace-logger n step IO.>> ♯ log-inboxes (env-inboxes (env step))

count+trace+inbox-logger : Logger
count+trace+inbox-logger n step = ♯ count-logger n step IO.>> ♯ trace+inbox-logger n step

actors-logger : Logger
actors-logger n step = log-actors+blocked (env step)

trace+actors-logger : Logger
trace+actors-logger n step = ♯ trace-logger n step IO.>> ♯ actors-logger n step
