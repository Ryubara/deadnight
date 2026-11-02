class_name BotBrain
extends RefCounted
## The part of a bot that decides. It reads the bot's beliefs and its own state (never the frame's
## zombies: the host takes them out of the client state once the perception has looked) and answers
## with a `BotIntent`. It runs at the profile's think rate, not every tick. The host does not trust
## it: an answer that is not an intent, or not a sane one, counts as a failure, and enough failures
## switch the brain off while the motor goes on alone (`BotClient`).


## What to do next. The base brain does nothing.
func think(_beliefs: BotBeliefs, _state: ClientState) -> BotIntent:
	return BotIntent.new()
