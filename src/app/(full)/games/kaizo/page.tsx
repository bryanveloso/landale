/**
 * Tracker widget to be sized to 384x418.
 * Browser window to be sized to 1920x1080.
 * */

const Page = () => {
  return (
    <main className="flex items-start justify-end">
      <div className="m-6 flex items-start">
        <div className="flex rounded-2xl bg-gradient-to-b from-gradient-lighter to-[#1E2229] shadow-xl shadow-black/50">
          <div className="relative m-3 flex rounded-lg bg-[#13141B] shadow-[inset_0_0_0_1px_#0E0D12]">
            <div className="bg-[#13141B] p-3">
              <div className="h-[416px] w-96 bg-red-500"></div>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
};

export default Page;
