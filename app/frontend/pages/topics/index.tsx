import { Head, useForm } from "@inertiajs/react";
import { FormEvent } from "react";

type Topic = {
  id: number;
  name: string;
  keywords: string[];
  subscribed: boolean;
  paused: boolean;
  discord_webhook: string | null;
};

type Props = {
  topics: Topic[];
  errors: Record<string, string[]>;
};

export default function Index({ topics, errors }: Props) {
  return (
    <>
      <Head title="Topics" />
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-2xl font-semibold">Topics</h1>
      </div>
      {topics.length === 0 ? (
        <p className="text-gray-600">No topics available yet. Check back soon.</p>
      ) : (
        <ul className="bg-white rounded border border-gray-200 divide-y">
          {topics.map((t) => (
            <TopicRow key={t.id} topic={t} errors={errors} />
          ))}
        </ul>
      )}
    </>
  );
}

function TopicRow({ topic, errors }: { topic: Topic; errors: Record<string, string[]> }) {
  return (
    <li className="p-3">
      <div className="flex justify-between items-start">
        <div>
          <div className="font-medium">
            {topic.name}
            {topic.subscribed && topic.paused && (
              <span className="ml-2 text-xs text-gray-500">(paused)</span>
            )}
          </div>
          <div className="text-xs text-gray-500">{topic.keywords.join(", ")}</div>
        </div>
        {!topic.subscribed && <SubscribeButton topicId={topic.id} />}
      </div>
      {topic.subscribed && <ManagePanel topic={topic} errors={errors} />}
    </li>
  );
}

function SubscribeButton({ topicId }: { topicId: number }) {
  const form = useForm({});
  const submit = (e: FormEvent) => {
    e.preventDefault();
    form.post(`/topics/${topicId}/subscription`);
  };
  return (
    <form onSubmit={submit}>
      <button
        type="submit"
        disabled={form.processing}
        className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
      >
        Subscribe
      </button>
    </form>
  );
}

function ManagePanel({
  topic,
  errors,
}: {
  topic: Topic;
  errors: Record<string, string[]>;
}) {
  const form = useForm({
    discord_webhook: topic.discord_webhook ?? "",
    active: !topic.paused,
  });

  const save = (e: FormEvent) => {
    e.preventDefault();
    form.patch(`/topics/${topic.id}/subscription`);
  };

  const togglePause = () => {
    form.transform((data) => ({ ...data, active: !data.active }));
    form.patch(`/topics/${topic.id}/subscription`);
  };

  const unsubscribe = () => {
    form.delete(`/topics/${topic.id}/subscription`);
  };

  return (
    <div className="mt-3 bg-gray-50 border border-gray-200 rounded p-3 space-y-3">
      <form onSubmit={save} className="space-y-2">
        <label className="block text-sm">
          <span className="font-medium">Discord webhook (optional)</span>
          <input
            className="mt-1 border rounded px-2 py-1 w-full"
            value={form.data.discord_webhook}
            onChange={(e) => form.setData("discord_webhook", e.target.value)}
            placeholder="https://discord.com/api/webhooks/..."
          />
          {errors.discord_webhook && (
            <div className="text-red-600 text-xs mt-1">
              {errors.discord_webhook.join(", ")}
            </div>
          )}
        </label>
        <div className="flex gap-2">
          <button
            type="submit"
            disabled={form.processing}
            className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
          >
            Save
          </button>
          <button
            type="button"
            onClick={togglePause}
            className="border px-3 py-1.5 rounded text-sm"
          >
            {topic.paused ? "Resume" : "Pause"}
          </button>
          <button
            type="button"
            onClick={unsubscribe}
            className="border border-red-200 text-red-600 px-3 py-1.5 rounded text-sm"
          >
            Unsubscribe
          </button>
        </div>
      </form>
    </div>
  );
}
