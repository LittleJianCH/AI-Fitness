<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { useSession } from '$lib/auth/session.svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { loadWorkout, type Scenario } from '$lib/api/read';
	import type { Workout } from '$lib/api/generated/client';
	import type { Snippet } from 'svelte';
	import Feedback from '$lib/components/Feedback.svelte';

	const session = useSession();

	let { id, scenario, children }: { id: string; scenario: Scenario; children: Snippet<[Workout]> } =
		$props();
	const query = createQuery(() => ({
		queryKey: ['workout', session.user?.id ?? 'demo', id, scenario],
		queryFn: ({ signal }) => loadWorkout(id, signal, scenario)
	}));
</script>

{#if query.isPending}<div class="status" role="status">{L.workout_loading()}</div>
{:else if query.data}{#if query.isError}<Feedback
			error={query.error}
			retry={() => query.refetch()}
		/>{/if}{@render children(query.data)}
{:else}<Feedback error={query.error} retry={() => query.refetch()} />{/if}
