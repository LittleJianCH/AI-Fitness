<script lang="ts">
	import { m as L } from '$lib/paraglide/messages.js';
	import { resolve } from '$app/paths';
</script>

<svelte:head><title>{L.demo_document()}</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">{L.eyebrow_product_preview()}</div>
		<h1>{L.demo_heading()}</h1>
		<p class="subtle">{L.demo_intro()}</p>
	</div>
</header>
<section class="surface">
	<h2>{L.demo_features_heading()}</h2>
	<p>{L.demo_features()}</p>
	<h2>{L.demo_scope_heading()}</h2>
	<p>{L.demo_privacy()}</p>
	<p>{L.demo_scope()}</p>
	<a class="button primary" href={resolve('/workouts')}>{L.demo_begin()}</a>
</section>

<style>
	section {
		max-width: 760px;
	}
	p {
		color: var(--muted);
		margin: 14px 0 28px;
		line-height: 1.8;
	}
	h2 {
		font-size: 20px;
	}
</style>
