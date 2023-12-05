/**
 * Tracker widget to be sized to 384x418.
 * Browser window to be sized to 1920x1080.
 * */

const Page = () => {
  return (
    <main className="flex items-start justify-end">
      <div className="m-6 flex items-start">
        <div className="from-shark-800 to-shark-900 flex rounded-2xl bg-gradient-to-b shadow-xl shadow-black/50">
          <div className="bg-shark-950 relative m-3 flex rounded-lg shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
            <div className="bg-shark-950 p-3">
              <div className="h-[416px] w-96 bg-red-500"></div>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
};

export default Page;
