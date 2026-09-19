<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import AccountSettings from '$lib/auth/components/AccountSettings.svelte';
	import { useSession } from '$lib/auth/session.svelte';
	import SettingsEditor from '$lib/settings/SettingsEditor.svelte';
	import { loadSettings, settingsKey } from '$lib/settings/api';
	import Feedback from '$lib/components/Feedback.svelte';
	const demo = import.meta.env.MODE === 'demo';
	const session = useSession();
	const query = createQuery(() => ({
		queryKey: settingsKey(session.user?.id),
		queryFn: ({ signal }) => loadSettings(signal),
		enabled: !demo && !!session.user
	}));
</script>

<svelte:head><title>设置 · AI Fitness</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">YOUR SETTINGS</div>
		<h1>设置</h1>
		<p class="subtle">软件偏好、个人身体参数、器材与账号。</p>
	</div>
</header>
{#if demo}<div class="status">设置需要登录真实账号，演示模式仅供查看。</div>
{:else}
	{#if query.isPending}<p role="status">正在加载设置…</p>{:else if query.isError}<Feedback
			error={query.error}
			retry={() => query.refetch()}
		/>{:else if query.data}<SettingsEditor initial={query.data} />{/if}
	<section class="section">
		<h2>账号与登录会话</h2>
		<AccountSettings />
	</section>
{/if}
