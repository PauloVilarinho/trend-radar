import { Head, useForm } from "@inertiajs/react";
import { FormEvent } from "react";

type Form = { id: number; name: string; keywords: string[]; active: boolean };
type Props = { topic: Form; errors: Record<string, string[]> };

export default function AdminTopicEdit({ topic, errors }: Props) {
  const form = useForm<Form>({
    id: topic.id,
    name: topic.name,
    keywords: topic.keywords,
    active: topic.active ?? true,
  });

  const submit = (e: FormEvent) => {
    e.preventDefault();
    form.patch(`/admin/topics/${topic.id}`);
  };

  const setKeywordsFromString = (s: string) => {
    form.setData(
      "keywords",
      s.split(",").map((k) => k.trim()).filter(Boolean)
    );
  };

  return (
    <>
      <Head title="Admin — Edit topic" />
      <h1 className="text-2xl font-semibold mb-4">Edit topic</h1>
      <form onSubmit={submit} className="max-w-lg space-y-4 bg-white p-4 rounded border">
        <Field label="Name" error={errors.name}>
          <input
            className="border rounded px-2 py-1 w-full"
            value={form.data.name}
            onChange={(e) => form.setData("name", e.target.value)}
          />
        </Field>
        <Field label="Keywords (comma-separated)" error={errors.keywords}>
          <input
            className="border rounded px-2 py-1 w-full"
            defaultValue={form.data.keywords.join(", ")}
            onBlur={(e) => setKeywordsFromString(e.target.value)}
          />
        </Field>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.data.active}
            onChange={(e) => form.setData("active", e.target.checked)}
          />
          Active
        </label>
        <button
          type="submit"
          disabled={form.processing}
          className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
        >
          Save
        </button>
      </form>
    </>
  );
}

function Field({
  label,
  error,
  children,
}: {
  label: string;
  error?: string[];
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="text-sm font-medium">{label}</span>
      <div className="mt-1">{children}</div>
      {error && <div className="text-red-600 text-xs mt-1">{error.join(", ")}</div>}
    </label>
  );
}
