import { AdminShell } from "@/components/admin-shell";
import { FieldOverview } from "@/components/field-overview";

export default function Home() {
  return (
    <AdminShell>
      <FieldOverview />
    </AdminShell>
  );
}

