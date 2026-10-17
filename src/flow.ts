import { createActor, createMachine } from 'xstate';

/** Only orchestration lives here. Rules commit before any presentation is played. */
export function createGameFlow() {
	return createActor(createMachine({
		id: 'hotel', initial: 'loading', on:{TITLE:'.title'},
		states: {
			loading: { on: { READY: 'title', FAIL: 'error' } },
			title: { on: { START: 'exploring' } },
			exploring: { on: { ENCOUNTER: 'forming', DIALOGUE: 'dialogue' } },
			dialogue: { on: { CLOSE: 'exploring' } },
			forming: { on: { FORMATION_READY: 'battle' } },
			battle: { on: { PLAY: 'presenting', VICTORY: 'victory', DEFEAT: 'defeat' } },
			presenting: { on: { DONE: 'battle' } },
			victory: { on: { CONTINUE: 'exploring' } },
			defeat: { on: { RETRY: 'battle' } },
			error: {},
		},
	})).start();
}
