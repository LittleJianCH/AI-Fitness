<svelte:head>
	<title>AI Fitness</title>
	<meta name="description" content="A personal fitness and training data system." />
</svelte:head>

<main>
	<p class="eyebrow">AI FITNESS</p>
	<h1>Your training, in focus.</h1>
	<p class="intro">A personal space for your workouts and training data.</p>
	<section aria-labelledby="status-heading">
		<h2 id="status-heading">Getting started</h2>
		<p>The web app is ready for development. Workout features are coming next.</p>
	</section>
</main>

<style>
	:global(body) {
		margin: 0;
		background: #f5f6f2;
		color: #1e3029;
		font-family: system-ui, sans-serif;
		line-height: 1.6;
	}
	main {
		max-width: 44rem;
		margin: 0 auto;
		padding: clamp(3rem, 10vw, 7rem) 1.5rem;
	}
	.eyebrow {
		color: #396149;
		font-size: 0.8rem;
		font-weight: 700;
		letter-spacing: 0.15em;
	}
	h1 {
		font-size: clamp(2.5rem, 7vw, 4rem);
		line-height: 1.1;
		letter-spacing: -0.04em;
		margin: 1.5rem 0;
	}
	.intro {
		font-size: 1.15rem;
	}
	section {
		margin-top: 3rem;
		padding-top: 1.5rem;
		border-top: 1px solid #c9d3cb;
	}
	h2 {
		font-size: 1.1rem;
	}
</style>
