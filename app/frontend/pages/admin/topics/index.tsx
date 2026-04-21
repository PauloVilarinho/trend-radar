import { Head, Link } from "@inertiajs/react";

type AdminTopic = {
  id: number;
  name: string;
  keywords: string[];
  active: boolean;
  subscriber_count: number;
};

export default function AdminTopicsIndex({ topics }: { topics: AdminTopic[] }) {
  return (
    <>
      <Head title="Admin — Topics" />
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-2xl font-semibold">Topics (admin)</h1>
        <Link
          href="/admin/topics/new"
          className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
        >
          New topic
        </Link>
      </div>
      {topics.length === 0 ? (
        <p className="text-gray-600">No topics yet. Create one to start curating.</p>
      ) : (
        <table className="w-full bg-white border border-gray-200 rounded text-sm">
          <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
            <tr>
              <th className="px-3 py-2">Name</th>
              <th className="px-3 py-2">Keywords</th>
              <th className="px-3 py-2">Active</th>
              <th className="px-3 py-2">Subscribers</th>
              <th className="px-3 py-2"></th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {topics.map((t) => (
              <tr key={t.id}>
                <td className="px-3 py-2 font-medium">{t.name}</td>
                <td className="px-3 py-2 text-gray-600">{t.keywords.join(", ")}</td>
                <td className="px-3 py-2">{t.active ? "yes" : "no"}</td>
                <td className="px-3 py-2">{t.subscriber_count}</td>
                <td className="px-3 py-2 text-right">
                  <Link href={`/admin/topics/${t.id}/edit`} className="text-blue-600">
                    Edit
                  </Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}
