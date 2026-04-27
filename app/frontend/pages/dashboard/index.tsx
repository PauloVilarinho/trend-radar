import { Head, router } from "@inertiajs/react"

type Match = {
  id: number
  topic: { id: number; name: string }
  story: {
    id: number
    hn_id: number
    title: string
    url: string | null
    score: number
    descendants: number
    hn_url: string
  }
  relevance_score: number
  velocity_score: number | null
  reason: string
  matched_at: string
}

export default function Dashboard({ matches }: { matches: Match[] }) {
  const markPosted = (id: number) =>
    router.post(`/matches/${id}/mark_posted`, {}, { preserveScroll: true })
  const dismiss = (id: number) =>
    router.post(`/matches/${id}/dismiss`, {}, { preserveScroll: true })

  return (
    <>
      <Head title="Dashboard" />
      <h1 className="text-2xl font-semibold mb-4">Climbing HN stories</h1>
      {matches.length === 0 ? (
        <p className="text-gray-600">No matches yet. Check back in a few minutes.</p>
      ) : (
        <ul className="space-y-3">
          {matches.map((m) => (
            <li key={m.id} className="bg-white rounded border border-gray-200 p-4">
              <div className="flex justify-between items-start gap-4">
                <div className="flex-1">
                  <div className="text-xs text-gray-500 mb-1">
                    <span className="font-medium text-gray-700">{m.topic.name}</span>
                    <span className="mx-1">·</span>
                    {new Date(m.matched_at).toLocaleString()}
                    {m.velocity_score !== null && (
                      <>
                        <span className="mx-1">·</span>
                        <span>+{m.velocity_score.toFixed(1)} pts/hr</span>
                      </>
                    )}
                  </div>
                  <a
                    href={m.story.url || m.story.hn_url}
                    target="_blank"
                    rel="noreferrer"
                    className="text-lg font-medium text-blue-700 hover:underline"
                  >
                    {m.story.title}
                  </a>
                  <div className="text-sm text-gray-500 mt-1">
                    {m.story.score} points · {m.story.descendants} comments ·{" "}
                    <a href={m.story.hn_url} target="_blank" rel="noreferrer" className="underline">
                      HN thread
                    </a>
                  </div>
                  <p className="text-sm text-gray-700 mt-2 italic">{m.reason}</p>
                </div>
                <div className="flex flex-col gap-1 text-xs">
                  <button
                    onClick={() => markPosted(m.id)}
                    className="bg-green-600 text-white px-2 py-1 rounded"
                  >
                    Mark as posted
                  </button>
                  <button
                    onClick={() => dismiss(m.id)}
                    className="bg-gray-200 text-gray-800 px-2 py-1 rounded"
                  >
                    Dismiss
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  )
}
